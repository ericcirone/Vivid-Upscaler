import SwiftUI

struct OptionsView: View {
    @Bindable var store: UpscaleStore

    var body: some View {
        Form {
            Section("Deblur") {
                Picker("Preprocessing", selection: $store.deblurMode) {
                    ForEach(store.installedDeblurModes) { deblurMode in
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

            Section("Face Restoration") {
                Toggle("Restore detected faces", isOn: $store.faceRestoreEnabled)
                    .disabled(!store.isFaceRestoreInstalled)
                if store.isFaceRestoreInstalled {
                    Picker("Preset", selection: $store.codeFormerPreset) {
                        ForEach(CodeFormerPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    Text(store.codeFormerPreset.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if store.codeFormerPreset == .custom {
                        LabeledContent("Fidelity weight") {
                            Text(store.codeFormerFidelityWeight, format: .number.precision(.fractionLength(2)))
                                .monospacedDigit()
                        }
                        Slider(value: $store.codeFormerFidelityWeight, in: 0...1, step: 0.01)
                    }
                    Text("Runs after deblur and before upscaling. Lower fidelity values reconstruct more strongly; higher values preserve more source identity.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if store.faceRestoreEnabled {
                        Text("Review identity-sensitive details carefully. Face restoration can change eyes, teeth, skin texture, and other features.")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                } else {
                    Text("Install Face Restore in the model manager to enable CodeFormer.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Mode") {
                Picker("Mode", selection: $store.mode) {
                    ForEach(store.installedUpscaleModes) { mode in
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

            if store.mode.supportsSeedVR2Settings {
                Section("SeedVR2 Restoration") {
                    Picker("Preset", selection: $store.seedVR2Preset) {
                        ForEach(SeedVR2Preset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    Text(store.seedVR2Preset.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if store.seedVR2Preset == .custom {
                        LabeledContent("Input noise") {
                            TextField("Input noise", value: $store.seedVR2InputNoiseScale, format: .number.precision(.fractionLength(2)))
                                .frame(width: 72)
                        }
                        Slider(value: $store.seedVR2InputNoiseScale, in: 0...1, step: 0.01)
                        LabeledContent("Latent noise") {
                            TextField("Latent noise", value: $store.seedVR2LatentNoiseScale, format: .number.precision(.fractionLength(2)))
                                .frame(width: 72)
                        }
                        Slider(value: $store.seedVR2LatentNoiseScale, in: 0...1, step: 0.01)
                        Picker("Color correction", selection: $store.seedVR2ColorCorrection) {
                            ForEach(SeedVR2ColorCorrection.allCases) { method in
                                Text(method.title).tag(method)
                            }
                        }
                        Text("Noise changes how the model reconstructs the image; increasing it does not simply increase quality.")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            if store.mode.supportsHYPIRSettings {
                Section("HYPIR Restoration") {
                    Picker("Preset", selection: $store.hypirPreset) {
                        ForEach(HYPIRPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    Text(store.hypirPreset.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if store.hypirPreset == .custom {
                        Picker("Patch size", selection: $store.hypirPatchSize) {
                            ForEach(HYPIRSettings.supportedPatchSizes, id: \.self) { value in
                                Text("\(value) px").tag(value)
                            }
                        }
                        Picker("Patch stride", selection: $store.hypirPatchStride) {
                            ForEach(HYPIRSettings.supportedPatchStrides(for: store.hypirPatchSize), id: \.self) { value in
                                Text("\(value) px").tag(value)
                            }
                        }
                        .onChange(of: store.hypirPatchSize) { _, patchSize in
                            store.hypirPatchStride = HYPIRSettings.normalizedPatchStride(
                                store.hypirPatchStride,
                                patchSize: patchSize
                            )
                        }
                        TextField("Prompt", text: $store.hypirPrompt, axis: .vertical)
                            .lineLimit(2...4)
                    } else if let settings = store.hypirPreset.settings {
                        LabeledContent("Patch configuration", value: "\(settings.patchSize) / \(settings.patchStride)")
                        Text(settings.prompt)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text("Smaller strides increase overlap and processing time. Strong prompts can invent identity-sensitive detail.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            if store.mode.supportsVariationSeed {
                Section("Variation") {
                    TextField("Variation Seed", value: $store.variationSeed, format: .number)
                    Button("Try Another Variation", systemImage: "dice") {
                        store.tryAnotherVariation()
                    }
                    Text("The seed selects a repeatable generative variation; its value is not a quality or strength setting.")
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
                        Text("1×").tag(1.0)
                        Text("1.5×").tag(1.5)
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
