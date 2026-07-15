import SwiftUI

struct ModelOnboardingView: View {
    enum Step { case welcome, choose, installing, complete }

    @Bindable var store: UpscaleStore
    @Environment(\.dismiss) private var dismiss
    @State private var step = Step.welcome
    @State private var selection: Set<String> = ["normal"]
    @State private var installError: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 8)
            content
            Spacer(minLength: 8)
            controls
        }
        .padding(32)
        .frame(width: 620, height: 500)
        .alert("Model installation failed", isPresented: Binding(
            get: { installError != nil },
            set: { if !$0 { installError = nil } }
        )) {
            Button("OK") { installError = nil; step = .choose }
        } message: { Text(installError ?? "") }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            Image(systemName: "sparkles.rectangle.stack").font(.system(size: 64)).foregroundStyle(.tint)
            Text("Welcome to Vivid Upscaler").font(.largeTitle.bold())
            Text("The app is ready, but it needs at least one upscaling model. Choose only what you need now—you can add more later.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 470)
        case .choose:
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose your models").font(.largeTitle.bold())
                Text("Normal is the best starting point for most photos.").foregroundStyle(.secondary)
                ForEach(ModelInfo.choices) { model in
                    Toggle(isOn: Binding(
                        get: { selection.contains(model.id) },
                        set: { selected in
                            if selected { selection.insert(model.id) }
                            else { selection.remove(model.id) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack { Text(model.title).font(.headline); Text(model.sizeNote).font(.caption).foregroundStyle(.secondary) }
                            Text(model.detail).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .padding(12)
                    .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
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
            Text("Vivid is ready").font(.largeTitle.bold())
            Text("Drop in a photo, choose a size, and start upscaling.").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack {
            if step == .choose { Button("Back") { step = .welcome } }
            Spacer()
            switch step {
            case .welcome:
                Button("Choose Models") { step = .choose }.buttonStyle(.borderedProminent)
            case .choose:
                Button("Download Selected") { beginInstall() }
                    .buttonStyle(.borderedProminent).disabled(selection.isEmpty)
            case .installing:
                EmptyView()
            case .complete:
                Button("Get Started") { store.showOnboarding = false; dismiss() }.buttonStyle(.borderedProminent)
            }
        }
    }

    private func beginInstall() {
        step = .installing
        store.progress = 0
        Task {
            do {
                try await store.installModels(ModelInfo.choices.map(\.id).filter(selection.contains))
                step = .complete
            } catch {
                installError = error.localizedDescription
            }
        }
    }
}
