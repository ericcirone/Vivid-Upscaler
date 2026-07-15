import SwiftUI

struct ModelOnboardingView: View {
    enum Step { case welcome, choose, installing, complete }

    @Bindable var store: UpscaleStore
    @Environment(\.dismiss) private var dismiss
    @State private var step = Step.welcome
    @State private var selection: Set<String> = []
    @State private var installError: String?
    @State private var pendingDeletion: ModelInfo?

    private var isManaging: Bool { !store.installedModelIDs.isEmpty }
    private var selectedDownloads: [String] {
        ModelInfo.choices.map(\.id).filter { selection.contains($0) && !store.installedModelIDs.contains($0) }
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 4)
            content
            Spacer(minLength: 4)
            controls
        }
        .padding(28)
        .frame(width: 700, height: 640)
        .onAppear { prepareSelection() }
        .alert("Model operation failed", isPresented: Binding(
            get: { installError != nil },
            set: { if !$0 { installError = nil } }
        )) {
            Button("OK") { installError = nil; step = .choose }
        } message: { Text(installError ?? "") }
        .confirmationDialog(
            "Delete \(pendingDeletion?.title ?? "model")?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { model in
            Button("Delete Model", role: .destructive) { deleteModel(model) }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { model in
            Text("The downloaded \(model.modelName) weights will be removed from this Mac. You can download them again later.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            Image(systemName: "sparkles.rectangle.stack").font(.system(size: 64)).foregroundStyle(.tint)
            Text("Welcome to Vivid Upscaler").font(.largeTitle.bold())
            Text("The app needs at least one compatible upscaling model. This Mac has \(store.systemRAMGB) GB of RAM, so models above that limit cannot be installed.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 520)
        case .choose:
            VStack(alignment: .leading, spacing: 12) {
                Text(isManaging ? "Manage models" : "Choose your models").font(.largeTitle.bold())
                Text("This Mac has \(store.systemRAMGB) GB of RAM. Normal is the best starting point for most photos.")
                    .foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(ModelInfo.choices) { model in modelRow(model) }
                    }
                    .padding(.vertical, 2)
                }
            }
        case .installing:
            ProgressView(value: store.progress)
                .progressViewStyle(.linear)
                .frame(maxWidth: 440)
            Text("Installing models…").font(.title.bold())
            Text(store.status).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center)
            Text("Keep this window open. Large models can take a while.").font(.caption).foregroundStyle(.tertiary)
        case .complete:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(.green)
            Text("Models are ready").font(.largeTitle.bold())
            Text("Installed models are marked in the model manager.").foregroundStyle(.secondary)
        }
    }

    private func modelRow(_ model: ModelInfo) -> some View {
        let installed = store.isInstalled(model)
        let compatible = store.canInstall(model)
        return HStack(alignment: .top, spacing: 12) {
            if installed {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).padding(.top, 2)
            } else {
                Toggle("", isOn: Binding(
                    get: { selection.contains(model.id) },
                    set: { selected in
                        if selected { selection.insert(model.id) } else { selection.remove(model.id) }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(!compatible)
                .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(model.title).font(.headline)
                    Text(model.modelName).font(.caption.monospaced()).foregroundStyle(.secondary)
                    if installed { Text("Installed").font(.caption.bold()).foregroundStyle(.green) }
                }
                Text(model.backend).font(.caption2.bold()).foregroundStyle(.secondary)
                Text(model.detail).font(.callout).foregroundStyle(.secondary)
                Text("Minimum \(model.minimumRAMGB) GB · Recommended \(model.recommendedRAMGB) GB · Large images \(model.largeImageRAMGB) GB · Tiling \(model.defaultTiling)")
                    .font(.caption2)
                    .foregroundStyle(compatible ? Color.secondary.opacity(0.7) : Color.red)
                if !compatible {
                    Text("Unavailable: requires \(model.minimumRAMGB) GB RAM")
                        .font(.caption.bold()).foregroundStyle(.red)
                }
            }
            Spacer(minLength: 8)
            if installed {
                Button(role: .destructive) { pendingDeletion = model } label: {
                    Image(systemName: "trash")
                }
                .help("Delete \(model.title) model")
            }
        }
        .padding(12)
        .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var controls: some View {
        HStack {
            if step == .choose, !isManaging { Button("Back") { step = .welcome } }
            Spacer()
            switch step {
            case .welcome:
                Button("Choose Models") { step = .choose }.buttonStyle(.borderedProminent)
            case .choose:
                if isManaging {
                    Button("Done") { dismiss() }
                }
                Button("Download Selected") { beginInstall() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedDownloads.isEmpty)
            case .installing:
                EmptyView()
            case .complete:
                Button("Done") { store.showOnboarding = false; dismiss() }.buttonStyle(.borderedProminent)
            }
        }
    }

    private func prepareSelection() {
        step = isManaging ? .choose : .welcome
        selection = store.installedModelIDs
        guard !isManaging else { return }
        if let preferred = ModelInfo.info(for: "normal"), store.canInstall(preferred) {
            selection.insert(preferred.id)
        } else if let fallback = ModelInfo.choices.first(where: store.canInstall) {
            selection.insert(fallback.id)
        }
    }

    private func beginInstall() {
        step = .installing
        store.progress = 0
        Task {
            do {
                try await store.installModels(selectedDownloads)
                selection = store.installedModelIDs
                step = .complete
            } catch {
                installError = error.localizedDescription
            }
        }
    }

    private func deleteModel(_ model: ModelInfo) {
        pendingDeletion = nil
        Task {
            do {
                try await store.deleteModel(model.id)
                selection.remove(model.id)
            } catch {
                installError = error.localizedDescription
            }
        }
    }
}
