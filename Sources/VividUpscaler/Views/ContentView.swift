import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var store: UpscaleStore
    @State private var isDropTargeted = false

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
                .interactiveDismissDisabled(store.installedModelIDs.isEmpty)
        }
        .alert("Vivid Upscaler", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
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
                if let progress = store.progress {
                    ProgressView(value: progress)
                } else {
                    ProgressView()
                }
                HStack {
                    Text(store.status).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button("Cancel", role: .destructive) { store.cancel() }
                }
            } else if store.completedOutputURL != nil {
                HStack {
                    Label("Upscale complete", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Spacer()
                    Button("Show in Finder") { store.revealOutput() }
                }
            }
        }
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
