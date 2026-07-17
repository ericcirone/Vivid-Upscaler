import SwiftUI

struct OptionsView: View {
    @Bindable var store: UpscaleStore

    var body: some View {
        Form {
            Section("Mode") {
                Picker("Mode", selection: $store.mode) {
                    ForEach(UpscaleMode.allCases) { mode in
                        Text(mode.isExperimental ? "\(mode.title) (Experimental)" : mode.title)
                            .tag(mode)
                            .disabled(mode.minimumRAMGB > store.systemRAMGB)
                    }
                }
                Text(store.mode.detail).font(.caption).foregroundStyle(.secondary)
                if store.mode.isExperimental {
                    Text("Opt-in generative restoration. Results may invent plausible detail; avoid for identity, text, or documentary-critical work.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Text("Requires \(store.mode.minimumRAMGB) GB RAM · This Mac: \(store.systemRAMGB) GB")
                    .font(.caption2)
                    .foregroundStyle(store.mode.minimumRAMGB <= store.systemRAMGB ? Color.secondary : Color.red)
            }

            Section("Deblur") {
                Picker("Preprocessing", selection: $store.deblurMode) {
                    ForEach(DeblurMode.allCases) { deblurMode in
                        Text(deblurMode.title)
                            .tag(deblurMode)
                            .disabled(deblurMode.minimumRAMGB > store.systemRAMGB)
                    }
                }
                Text(store.deblurMode.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if store.deblurMode != .none {
                    Text("Runs before upscaling · Requires \(store.deblurMode.minimumRAMGB) GB RAM")
                        .font(.caption2)
                        .foregroundStyle(store.deblurMode.minimumRAMGB <= store.systemRAMGB ? Color.secondary : Color.red)
                } else {
                    Text("Vivid does not guess the blur type; choose Motion Blur or Out of Focus when needed.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
                if store.supportsOutputQuality {
                    QualitySlider(quality: $store.quality)
                } else {
                    Text("Saved beside the original photo.").font(.caption).foregroundStyle(.secondary)
                }
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

private struct QualitySlider: View {
    @Binding var quality: Double

    private var selectedPreset: OutputQualityPreset {
        .nearest(to: quality)
    }

    private var stopPosition: Binding<Double> {
        Binding(
            get: { Double(selectedPreset.index) },
            set: { newValue in
                let lastIndex = OutputQualityPreset.allCases.count - 1
                let index = min(max(Int(newValue.rounded()), 0), lastIndex)
                quality = Double(OutputQualityPreset.allCases[index].rawValue)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quality")

            GeometryReader { geometry in
                let stopCount = OutputQualityPreset.allCases.count
                let trackInset: CGFloat = 10

                Slider(
                    value: stopPosition,
                    in: 0...Double(stopCount - 1),
                    step: 1
                )
                .labelsHidden()
                .frame(width: geometry.size.width)
                .position(x: geometry.size.width / 2, y: 8)

                ForEach(OutputQualityPreset.allCases) { preset in
                    let fraction = CGFloat(preset.index) / CGFloat(stopCount - 1)
                    let x = trackInset + ((geometry.size.width - (trackInset * 2)) * fraction)

                    VStack(spacing: 1) {
                        Text(preset.title)
                        Text("\(preset.rawValue)%")
                            .font(.caption2)
                    }
                    .foregroundStyle(preset == selectedPreset ? .primary : .secondary)
                    .frame(width: 60)
                    .position(x: x, y: 39)
                }
            }
            .frame(height: 58)
            .padding(.horizontal, 28)

            Text("Saved beside the original photo.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(selectedPreset.title), \(selectedPreset.rawValue) percent")
    }
}
