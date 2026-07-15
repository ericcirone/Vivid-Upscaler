import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var store: UpscaleStore
    @State private var isDropTargeted = false
    @State private var isShowingLog = false

    var body: some View {
        HSplitView {
            VStack(spacing: 20) {
                header
                DropZoneView(inputURL: store.inputURL, isTargeted: isDropTargeted) {
                    store.chooseInput()
                }
                .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
                    handleDrop(providers)
                }

                outputSummary
                progressArea
                Spacer(minLength: 0)
            }
            .padding(28)
            .frame(minWidth: 470)

            OptionsView(store: store)
                .frame(width: 285)
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
        .alert("Replace existing output?", isPresented: Binding(
            get: { store.pendingOverwriteURL != nil },
            set: { if !$0 { store.pendingOverwriteURL = nil } }
        )) {
            Button("Cancel", role: .cancel) { store.pendingOverwriteURL = nil }
            Button("Replace", role: .destructive) {
                store.pendingOverwriteURL = nil
                Task { await store.upscale(overwrite: true) }
            }
        } message: {
            Text(store.pendingOverwriteURL?.lastPathComponent ?? "This file already exists.")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Vivid Upscaler").font(.largeTitle.bold())
                Text("Native controls, powered by the Vivid CLI").foregroundStyle(.secondary)
            }
            Spacer()
            Button("Models") { store.showOnboarding = true }
            SettingsLink { Image(systemName: "gearshape") }
                .help("Settings")
        }
    }

    @ViewBuilder
    private var outputSummary: some View {
        if let output = store.outputURL {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Output").font(.caption).foregroundStyle(.secondary)
                    Text(output.lastPathComponent).font(.callout.monospaced()).textSelection(.enabled)
                    Text(output.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
        }
    }

    private var progressArea: some View {
        VStack(spacing: 10) {
            if store.isRunning {
                HStack(spacing: 10) {
                    if let progress = store.progress {
                        ProgressView(value: progress)
                    } else {
                        ProgressView()
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let elapsed = store.formattedRunningElapsedTime(at: context.date)
                        Text(elapsed)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 62, alignment: .trailing)
                            .accessibilityLabel("Elapsed time \(elapsed)")
                    }
                }
                HStack {
                    Text(store.status).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button("Cancel", role: .destructive) { store.cancel() }
                }
                HStack {
                    Button("View Full Log") { isShowingLog = true }
                    Spacer()
                }
            } else if store.completedOutputURL != nil {
                HStack {
                    Label(completionLabel, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Spacer()
                    Button("Show in Finder") { store.revealOutput() }
                }
            }
        }
    }

    private var completionLabel: String {
        guard let elapsed = store.formattedElapsedTime else { return "Upscale complete" }
        return "Upscale complete in \(elapsed)"
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
            else { url = item as? URL }
            if let url { Task { @MainActor in store.selectInput(url) } }
        }
        return true
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
