import SwiftUI

struct OptionsView: View {
    @Bindable var store: UpscaleStore

    var body: some View {
        Form {
            Section("Mode") {
                Picker("Mode", selection: $store.mode) {
                    ForEach(UpscaleMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                Text(store.mode.detail).font(.caption).foregroundStyle(.secondary)
            }

            Section("Size") {
                Picker("Sizing", selection: $store.sizingKind) {
                    ForEach(SizingKind.allCases) { kind in Text(kind.title).tag(kind) }
                }
                .pickerStyle(.segmented)

                if store.sizingKind == .scale {
                    Picker("Scale", selection: $store.scale) {
                        Text("2×").tag(2.0)
                        Text("3×").tag(3.0)
                        Text("4×").tag(4.0)
                    }
                } else {
                    TextField("Short edge", value: $store.resolution, format: .number)
                    TextField("Max long edge", value: $store.maxResolution, format: .number)
                }
            }

            Section("Format") {
                Picker("Output", selection: $store.format) {
                    ForEach(OutputFormat.allCases) { format in Text(format.title).tag(format) }
                }
                Text("Saved beside the original photo.").font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Button {
                    store.requestUpscale()
                } label: {
                    Label("Upscale Photo", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.inputURL == nil || store.isRunning)
            }
        }
        .formStyle(.grouped)
    }
}
