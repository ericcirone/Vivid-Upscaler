import SwiftUI

struct OptionsView: View {
    @Bindable var store: UpscaleStore

    var body: some View {
        VStack(spacing: 0) {
            Form {
                modelSection
                sizeSection
                outputSection
                enhancementSection
                seedVR2Section
                hypirSection
                variationSection
            }
            .formStyle(.grouped)
            .disabled(store.isRunning)

            Divider()
            actionBar
        }
    }

    // MARK: Model

    private var modelSection: some View {
        Section {
            Picker("Mode", selection: $store.mode) {
                ForEach(store.installedUpscaleModes) { mode in
                    Text(mode.isExperimental ? "\(mode.title) (Experimental)" : mode.title)
                        .tag(mode)
                        .disabled(mode.minimumRAMGB > store.systemRAMGB)
                }
            }
            .disabled(store.keepsOriginalSize)
            if store.keepsOriginalSize {
                Text("Upscaling is skipped at Original size; only enhancements run.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(store.mode.detail).font(.caption).foregroundStyle(.secondary)
            }
            if store.mode.isExperimental && !store.keepsOriginalSize {
                Text("Opt-in generative restoration. Results may invent plausible detail; avoid for identity, text, or documentary-critical work.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if store.mode.minimumRAMGB > store.systemRAMGB {
                Text("Requires \(store.mode.minimumRAMGB) GB RAM · This Mac: \(store.systemRAMGB) GB")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            if store.mode.supportsNoiseReduction && !store.keepsOriginalSize {
                LabeledContent("Noise reduction") {
                    Text(store.noiseReduction, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                }
                Slider(value: $store.noiseReduction, in: 0...1, step: 0.05) {
                    Text("Noise reduction")
                } minimumValueLabel: {
                    Text("Grain").font(.caption2)
                } maximumValueLabel: {
                    Text("Smooth").font(.caption2)
                }
                .labelsHidden()
            }
        } header: {
            HStack {
                Text("Model")
                Spacer()
                Button("Manage Models…") { store.showOnboarding = true }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
    }

    // MARK: Size

    private var sizeSection: some View {
        Section("Size") {
            Picker("Sizing", selection: $store.sizingKind) {
                ForEach(SizingKind.allCases) { kind in Text(kind.title).tag(kind) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if store.sizingKind == .scale {
                Picker("Scale", selection: $store.scale) {
                    Text("1×").tag(1.0)
                    Text("1.5×").tag(1.5)
                    Text("2×").tag(2.0)
                    Text("3×").tag(3.0)
                    Text("4×").tag(4.0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if store.scale == 1 {
                    Text("Keeps the original size while restoring detail.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if store.sizingKind == .resolution {
                TextField("Short edge (px)", value: $store.resolution, format: .number)
                TextField("Max long edge (px)", value: $store.maxResolution, format: .number)
            } else {
                Text("Keeps the original dimensions and skips the upscaling model.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !store.options.hasEnhancements {
                    Text("Turn on Photo Restore or another enhancement below.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            if let item = store.selectedItem ?? store.items.first,
               let output = store.outputPixelSize(for: item) {
                LabeledContent(store.items.count > 1 ? "Selected photo" : "Output size") {
                    Text("\(ImageInfo.formatted(output)) px")
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: Output

    private var outputSection: some View {
        Section("Output") {
            Picker("Format", selection: $store.format) {
                ForEach(OutputFormat.allCases) { format in Text(format.title).tag(format) }
            }
            if store.supportsOutputQuality {
                QualitySlider(quality: $store.quality)
            }
            if store.format == .jxl {
                Text("Color-managed JPEG XL requires cjxl: brew install jpeg-xl")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Save to") {
                Menu {
                    Button("Same Folder as Original") { store.outputDirectory = nil }
                    Button("Choose Folder…") { store.chooseOutputDirectory() }
                    if let directory = store.outputDirectory {
                        Divider()
                        Button("Show \(directory.lastPathComponent) in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([directory])
                        }
                    }
                } label: {
                    Text(store.outputDirectory?.lastPathComponent ?? "Same folder as original")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .help(store.outputDirectory?.path ?? "Results are saved beside each original photo")
        }
    }

    // MARK: Enhancements

    private var enhancementSection: some View {
        Section("Enhancements") {
            if store.isPhotoRestoreInstalled {
                photoRestoreControls
            }

            if store.installedDeblurModes.count > 1 {
                Picker("Deblur", selection: $store.deblurMode) {
                    ForEach(store.installedDeblurModes) { deblurMode in
                        Text(deblurMode.title)
                            .tag(deblurMode)
                            .disabled(deblurMode.minimumRAMGB > store.systemRAMGB)
                    }
                }
                if store.deblurMode == .none {
                    Text("Choose Motion Blur for camera shake or Out of Focus for missed focus.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(store.deblurMode.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if store.deblurMode.minimumRAMGB > store.systemRAMGB {
                        Text("Requires \(store.deblurMode.minimumRAMGB) GB RAM")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            }

            if store.isFaceRestoreInstalled {
                Toggle("Restore faces", isOn: $store.faceRestoreEnabled)
                if store.faceRestoreEnabled {
                    Picker("Face preset", selection: $store.codeFormerPreset) {
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
                        Text("Lower values reconstruct more strongly; higher values preserve more source identity.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("Review results carefully: face restoration can change eyes, teeth, and skin texture.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            if !store.isPhotoRestoreInstalled || store.installedDeblurModes.count == 1 || !store.isFaceRestoreInstalled {
                Button("Get Enhancement Models…") { store.showOnboarding = true }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            if let order = enhancementOrderDescription {
                Text(order)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var photoRestoreControls: some View {
        Toggle("Restore photo", isOn: $store.photoRestoreEnabled)
        if store.photoRestoreEnabled {
            Picker("Restore preset", selection: $store.photoRestorePreset) {
                ForEach(PhotoRestorePreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            Text(store.photoRestorePreset.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            if store.photoRestorePreset == .custom {
                LabeledContent("Strength") {
                    Text(store.photoRestoreStrength, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                }
                Slider(value: $store.photoRestoreStrength, in: 0...1, step: 0.05) {
                    Text("Strength")
                } minimumValueLabel: {
                    Text("Original").font(.caption2)
                } maximumValueLabel: {
                    Text("Clean").font(.caption2)
                }
                .labelsHidden()
                Picker("Detail", selection: $store.photoRestoreDetail) {
                    ForEach(PhotoRestoreDetail.allCases) { detail in
                        Text(detail.title).tag(detail)
                    }
                }
                .pickerStyle(.segmented)
            }
            Text("Tones and colors always come from the original; only noise, grain, and compression artifacts are replaced.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if store.options.photoRestoreOptions.resolvedSettings.detail == .sharp {
                Text("Sharp detail can reconstruct fine texture that was not in the original.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var enhancementOrderDescription: String? {
        let steps = store.options.preprocessingPipeline.steps
        guard !steps.isEmpty else { return nil }
        let names = steps.map { step in
            switch step {
            case .photoRestore: "photo restore"
            case .deblur: "deblur"
            case .faceRestore: "face restoration"
            }
        }
        let sequence = names.count > 1
            ? names.dropLast().joined(separator: ", ") + ", then " + names.last!
            : names[0]
        let prefix = store.keepsOriginalSize ? "Runs at the original size" : "Runs before upscaling"
        return "\(prefix): \(sequence)."
    }

    // MARK: Generative settings

    @ViewBuilder
    private var seedVR2Section: some View {
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
    }

    @ViewBuilder
    private var hypirSection: some View {
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
                    LabeledContent("Restoration strength") {
                        Text(store.hypirRestorationStrength, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                    }
                    Slider(value: $store.hypirRestorationStrength, in: 0...1, step: 0.01)
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
                    LabeledContent("Restoration strength") {
                        Text(settings.restorationStrength, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                    }
                    LabeledContent("Patch configuration", value: "\(settings.patchSize) / \(settings.patchStride)")
                    Text(settings.prompt)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text("Strength blends source and HYPIR-generated texture; it does not shorten inference. Smaller strides increase overlap and processing time.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Strong prompts and higher strength can invent identity-sensitive detail.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var variationSection: some View {
        if store.mode.supportsVariationSeed {
            Section("Variation") {
                TextField("Variation Seed", value: $store.variationSeed, format: .number.grouping(.never))
                Button("Try Another Variation", systemImage: "dice") {
                    store.tryAnotherVariation()
                }
                Text("The seed selects a repeatable generative variation; its value is not a quality or strength setting.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Action

    private var actionBar: some View {
        Group {
            if store.isRunning {
                Button(role: .destructive) {
                    store.cancel()
                } label: {
                    Label(store.isCancelling ? "Stopping…" : "Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(store.isCancelling)
            } else {
                Button {
                    store.requestUpscale()
                } label: {
                    Label(upscaleTitle, systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    store.items.isEmpty
                        || !store.hasInstalledUpscaleModel
                        || (store.keepsOriginalSize && !store.options.hasEnhancements)
                )
            }
        }
        .controlSize(.large)
        .padding(12)
    }

    private var upscaleTitle: String {
        let verb = store.keepsOriginalSize ? "Restore" : "Upscale"
        switch store.items.count {
        case 0, 1: return "\(verb) Photo"
        default: return "\(verb) \(store.items.count) Photos"
        }
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
        }
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(selectedPreset.title), \(selectedPreset.rawValue) percent")
    }
}
