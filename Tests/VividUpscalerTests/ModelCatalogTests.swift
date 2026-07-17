import Foundation
import Testing
@testable import VividUpscaler

@Suite("Model catalog")
struct ModelCatalogTests {
    @Test("Catalog exposes every processing mode")
    func exposesEveryMode() {
        #expect(ModelInfo.choices.map(\.id) == ["fast", "normal", "normal-hq", "advanced", "maximum", "maximum-experimental", "deblur-motion", "deblur-defocus", "face-restore"])
        #expect(Set(ModelInfo.choices.compactMap(\.mode)) == Set(UpscaleMode.allCases))
        #expect(Set(ModelInfo.choices.compactMap(\.deblurMode)) == Set([DeblurMode.motion, DeblurMode.defocus]))
    }

    @Test("Minimum RAM policy matches the catalog")
    func minimumRAMPolicy() {
        let requirements = Dictionary(uniqueKeysWithValues: ModelInfo.choices.map { ($0.id, $0.minimumRAMGB) })
        #expect(requirements["fast"] == 8)
        #expect(requirements["normal"] == 16)
        #expect(requirements["normal-hq"] == 16)
        #expect(requirements["advanced"] == 16)
        #expect(requirements["maximum"] == 24)
        #expect(requirements["maximum-experimental"] == 24)
        #expect(requirements["deblur-motion"] == 16)
        #expect(requirements["deblur-defocus"] == 16)
        #expect(requirements["face-restore"] == 8)
    }

    @Test("Catalog uses the requested model and backend mapping")
    func requestedModelMapping() {
        let catalog = Dictionary(uniqueKeysWithValues: ModelInfo.choices.map { ($0.id, ($0.modelName, $0.backend)) })
        #expect(catalog["fast"]?.0 == "mlx-community/Real-ESRGAN-general-x4v3")
        #expect(catalog["fast"]?.1 == "MLX")
        #expect(catalog["normal"]?.0 == "mlx-community/Real-ESRGAN-x4plus")
        #expect(catalog["normal"]?.1 == "MLX")
        #expect(catalog["normal-hq"]?.0 == "4xNomosWebPhoto_esrgan")
        #expect(catalog["normal-hq"]?.1 == "PyTorch MPS via Spandrel")
        #expect(catalog["advanced"]?.0 == "SeedVR2 3B 8-bit")
        #expect(catalog["advanced"]?.1 == "Native MLX")
        #expect(catalog["maximum"]?.0 == "SeedVR2 3B source precision")
        #expect(catalog["maximum"]?.1 == "Native MLX")
        #expect(catalog["maximum-experimental"]?.0 == "HYPIR-SD2")
        #expect(catalog["maximum-experimental"]?.1 == "PyTorch MPS, experimental")
        #expect(UpscaleMode.maximumExperimental.title == "Maximum Experimental")
        #expect(UpscaleMode.maximumExperimental.isExperimental)
        #expect(!UpscaleMode.maximum.isExperimental)
        #expect(catalog["deblur-motion"]?.0 == "Restormer Motion Deblurring")
        #expect(catalog["deblur-motion"]?.1 == "PyTorch MPS")
        #expect(catalog["deblur-defocus"]?.0 == "Restormer Single-Image Defocus Deblurring")
        #expect(catalog["deblur-defocus"]?.1 == "PyTorch MPS")
        #expect(catalog["face-restore"]?.0 == "CodeFormer v0.1.0")
        #expect(catalog["face-restore"]?.1 == "PyTorch MPS via Vivid adapter")
    }

    @Test("Generative and SeedVR2 capabilities match the model contract")
    func generativeCapabilities() {
        #expect(UpscaleMode.allCases.filter(\.supportsVariationSeed) == [.advanced, .maximum, .maximumExperimental])
        #expect(UpscaleMode.allCases.filter(\.supportsSeedVR2Settings) == [.advanced, .maximum])
        #expect(SeedVR2Preset.faithful.settings == .init(inputNoiseScale: 0, latentNoiseScale: 0, colorCorrection: .lab))
        #expect(SeedVR2Preset.highResolutionCleanup.settings == .init(inputNoiseScale: 0.15, latentNoiseScale: 0, colorCorrection: .lab))
        #expect(SeedVR2Preset.softerDetail.settings == .init(inputNoiseScale: 0, latentNoiseScale: 0.08, colorCorrection: .wavelet))
        #expect(SeedVR2Options(preset: .custom, customInputNoiseScale: -1, customLatentNoiseScale: 2).resolvedSettings == .init(inputNoiseScale: 0, latentNoiseScale: 1, colorCorrection: .lab))
    }

    @Test("CodeFormer presets clamp custom fidelity and preprocessing order is stable")
    func codeFormerContract() {
        #expect(CodeFormerPreset.enhance.fidelityWeight == 0.4)
        #expect(CodeFormerPreset.balanced.fidelityWeight == 0.7)
        #expect(CodeFormerPreset.faithful.fidelityWeight == 0.9)
        #expect(CodeFormerOptions(isEnabled: true, preset: .custom, customFidelityWeight: -1).resolvedFidelityWeight == 0)
        #expect(CodeFormerOptions(isEnabled: true, preset: .custom, customFidelityWeight: 2).resolvedFidelityWeight == 1)

        let faceOptions = CodeFormerOptions(isEnabled: true, preset: .balanced)
        let pipeline = PreprocessingPipeline(deblurMode: .motion, codeFormerOptions: faceOptions)
        #expect(pipeline.steps == [.deblur(.motion), .faceRestore(faceOptions)])
    }

    @Test("App options forward variation and restoration settings to the CLI")
    func cliRestorationArguments() {
        let input = URL(fileURLWithPath: "/tmp/input.png")
        let output = URL(fileURLWithPath: "/tmp/output.png")
        let options = UpscaleOptions(
            mode: .advanced,
            codeFormerOptions: .init(isEnabled: true, preset: .faithful),
            generativeOptions: .init(variationSeed: 123),
            seedVR2Options: .init(preset: .softerDetail),
            sizingKind: .scale,
            scale: 2,
            resolution: 2048,
            maxResolution: 4096,
            format: .png,
            quality: 90
        )

        let arguments = VividCLI.upscaleArguments(input: input, output: output, options: options)
        func containsPair(_ flag: String, _ value: String) -> Bool {
            zip(arguments, arguments.dropFirst()).contains { $0 == flag && $1 == value }
        }
        #expect(containsPair("--seed", "123"))
        #expect(containsPair("--seedvr2-preset", "softer-detail"))
        #expect(containsPair("--input-noise-scale", "0.0"))
        #expect(containsPair("--latent-noise-scale", "0.08"))
        #expect(containsPair("--color-correction", "wavelet"))
        #expect(arguments.contains("--face-restore"))
        #expect(containsPair("--codeformer-preset", "faithful"))
        #expect(containsPair("--codeformer-fidelity", "0.9"))
    }

    @Test("Models below the machine RAM threshold are rejected")
    func compatibility() {
        let maximum = ModelInfo.info(for: "maximum")!
        #expect(!maximum.isCompatible(withRAMGB: 16))
        #expect(maximum.isCompatible(withRAMGB: 24))

        let fast = ModelInfo.info(for: "fast")!
        #expect(!fast.isCompatible(withRAMGB: 7))
        #expect(fast.isCompatible(withRAMGB: 8))
    }

    @Test("Store uses detected physical memory for install eligibility")
    @MainActor
    func storeUsesDetectedMemory() {
        let store = UpscaleStore(systemMemoryBytes: 8 * 1_073_741_824)
        #expect(store.systemRAMGB == 8)
        #expect(store.canInstall(ModelInfo.info(for: "fast")!))
        #expect(!store.canInstall(ModelInfo.info(for: "normal")!))
        #expect(!store.canInstall(ModelInfo.info(for: "maximum")!))
        store.installedModelIDs = ["deblur-motion"]
        #expect(!store.hasInstalledUpscaleModel)
        store.installedModelIDs.insert("fast")
        #expect(store.hasInstalledUpscaleModel)
    }

    @Test("Selectors only expose downloaded models")
    @MainActor
    func selectorsOnlyExposeInstalledModels() {
        let store = UpscaleStore(systemMemoryBytes: 32 * 1_073_741_824)
        store.installedModelIDs = ["fast", "maximum", "deblur-motion"]

        #expect(store.installedUpscaleModes == [.fast, .maximum])
        #expect(store.installedDeblurModes == [.none, .motion])
    }

    @Test("Removed selections fall back to downloaded choices")
    @MainActor
    func removedSelectionsFallBackToDownloadedChoices() {
        let store = UpscaleStore(systemMemoryBytes: 32 * 1_073_741_824)
        store.installedModelIDs = ["fast", "normal", "deblur-motion", "face-restore"]
        store.mode = .normal
        store.deblurMode = .motion
        store.faceRestoreEnabled = true

        store.installedModelIDs = ["fast"]

        #expect(store.mode == .fast)
        #expect(store.deblurMode == .none)
        #expect(!store.faceRestoreEnabled)
    }

    @Test("Store starts with default settings each time")
    @MainActor
    func storeStartsWithDefaultSettingsEachTime() {
        let firstStore = UpscaleStore(systemMemoryBytes: 32 * 1_073_741_824)
        firstStore.mode = .maximum
        firstStore.deblurMode = .motion
        firstStore.faceRestoreEnabled = true
        firstStore.sizingKind = .resolution
        firstStore.scale = 4
        firstStore.resolution = 1_024
        firstStore.maxResolution = 8_192
        firstStore.format = .jpg
        firstStore.quality = 60

        let restartedStore = UpscaleStore(systemMemoryBytes: 32 * 1_073_741_824)

        #expect(restartedStore.mode == .normal)
        #expect(restartedStore.deblurMode == .none)
        #expect(!restartedStore.faceRestoreEnabled)
        #expect(restartedStore.sizingKind == .scale)
        #expect(restartedStore.scale == 2)
        #expect(restartedStore.resolution == 2_048)
        #expect(restartedStore.maxResolution == 4_096)
        #expect(restartedStore.format == .same)
        #expect(restartedStore.quality == Double(OutputQualityPreset.high.rawValue))
    }
}
