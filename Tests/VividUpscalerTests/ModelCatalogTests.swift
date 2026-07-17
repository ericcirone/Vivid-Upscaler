import Testing
@testable import VividUpscaler

@Suite("Model catalog")
struct ModelCatalogTests {
    @Test("Catalog exposes every processing mode")
    func exposesEveryMode() {
        #expect(ModelInfo.choices.map(\.id) == ["fast", "normal", "normal-hq", "advanced", "maximum", "maximum-experimental", "deblur-motion", "deblur-defocus"])
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
        store.installedModelIDs = ["fast", "normal", "deblur-motion"]
        store.mode = .normal
        store.deblurMode = .motion

        store.installedModelIDs = ["fast"]

        #expect(store.mode == .fast)
        #expect(store.deblurMode == .none)
    }
}
