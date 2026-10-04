import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var store: UpscaleStore
    @Environment(\.openWindow) private var openWindow
    @State private var isDropTargeted = false
    @State private var isShowingLog = false

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                photoArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !store.items.isEmpty {
                    Divider()
                    StatusBarView(store: store) { isShowingLog = true }
                }
            }
            .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if isDropTargeted && !store.items.isEmpty {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        .padding(6)
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)

            OptionsView(store: store)
                .frame(minWidth: 300, idealWidth: 320, maxWidth: 400)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.chooseInputs()
                } label: {
                    Label("Add Photos", systemImage: "plus")
                }
                .help("Add photos or folders (⌘O)")

                Button {
                    store.showOnboarding = true
                } label: {
                    Label("Models", systemImage: "shippingbox")
                }
                .help(store.isRunning ? "Models can be managed after processing finishes" : "Download or remove models")
                .disabled(store.isRunning)
            }
        }
        .task { await store.refreshSetupState() }
        .sheet(isPresented: $store.showOnboarding) {
            ModelOnboardingView(store: store)
                .interactiveDismissDisabled(!store.hasInstalledUpscaleModel)
        }
        .sheet(isPresented: $isShowingLog) {
            ProcessingLogView(store: store)
        }
        .alert("Vivid Upscaler", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
            if !store.logLines.isEmpty {
                Button("Show Log") {
                    store.errorMessage = nil
                    isShowingLog = true
                }
            }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .alert("Command Line Tool Installed", isPresented: Binding(
            get: { store.noticeMessage != nil },
            set: { if !$0 { store.noticeMessage = nil } }
        )) {
            Button("OK") { store.noticeMessage = nil }
        } message: {
            Text(store.noticeMessage ?? "")
        }
        .alert(
            overwriteTitle,
            isPresented: Binding(
                get: { store.pendingOverwrite != nil },
                set: { if !$0 { store.pendingOverwrite = nil } }
            ),
            presenting: store.pendingOverwrite
        ) { confirmation in
            Button("Replace", role: .destructive) { store.startUpscale(policy: .replace) }
            if confirmation.totalCount > confirmation.existingOutputs.count {
                Button("Skip Existing") { store.startUpscale(policy: .skip) }
            }
            Button("Cancel", role: .cancel) { store.pendingOverwrite = nil }
        } message: { confirmation in
            Text(overwriteMessage(confirmation))
        }
    }

    @ViewBuilder
    private var photoArea: some View {
        if store.items.isEmpty {
            DropZoneView(isTargeted: isDropTargeted) { store.chooseInputs() }
                .padding(24)
        } else if store.items.count == 1, let item = store.items.first {
            SinglePhotoView(store: store, item: item, compare: compare)
        } else {
            QueueListView(store: store, compare: compare)
        }
    }

    private var overwriteTitle: String {
        guard let confirmation = store.pendingOverwrite else { return "Replace existing results?" }
        return confirmation.existingOutputs.count == 1
            ? "Replace existing result?"
            : "Replace \(confirmation.existingOutputs.count) existing results?"
    }

    private func overwriteMessage(_ confirmation: UpscaleStore.OverwriteConfirmation) -> String {
        if confirmation.existingOutputs.count == 1, let existing = confirmation.existingOutputs.first {
            return "\(existing.lastPathComponent) already exists in \(existing.deletingLastPathComponent().lastPathComponent)."
        }
        let names = confirmation.existingOutputs.prefix(3).map(\.lastPathComponent).joined(separator: ", ")
        let more = confirmation.existingOutputs.count > 3 ? ", and \(confirmation.existingOutputs.count - 3) more" : ""
        return "These results already exist: \(names)\(more)."
    }

    private func compare(_ item: BatchItem) {
        if store.prepareComparison(for: item) {
            openWindow(id: "comparison-preview")
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }
        let collector = DroppedURLCollector(expected: fileProviders.count) { urls in
            Task { @MainActor in store.addInputs(urls) }
        }
        for provider in fileProviders {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                collector.add(url)
            }
        }
        return true
    }
}

/// Gathers URLs from several asynchronous item providers, preserving drop order.
private final class DroppedURLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int
    private var urls: [URL] = []
    private let completion: @Sendable ([URL]) -> Void

    init(expected: Int, completion: @escaping @Sendable ([URL]) -> Void) {
        remaining = expected
        self.completion = completion
    }

    func add(_ url: URL?) {
        lock.lock()
        if let url { urls.append(url) }
        remaining -= 1
        let finished = remaining == 0
        let collected = urls
        lock.unlock()
        if finished {
            completion(collected.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })
        }
    }
}

private struct ProcessingLogView: View {
    @Bindable var store: UpscaleStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Processing Log").font(.headline)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.fullLog, forType: .string)
                }
                .disabled(store.logLines.isEmpty)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(store.fullLog.isEmpty ? "Waiting for output…" : store.fullLog)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    Color.clear.frame(height: 1).id("log-bottom")
                }
                .onAppear { proxy.scrollTo("log-bottom", anchor: .bottom) }
                .onChange(of: store.logLines.count) {
                    proxy.scrollTo("log-bottom", anchor: .bottom)
                }
            }
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 380)
    }
}
