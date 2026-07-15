import Testing
@testable import VividUpscaler

@Suite("Model catalog")
struct ModelCatalogTests {
    @Test("Catalog exposes every processing mode")
    func exposesEveryMode() {
        #expect(ModelInfo.choices.map(\.id) == ["fast", "normal", "normal-hq", "advanced", "maximum"])
        #expect(Set(ModelInfo.choices.map(\.mode)) == Set(UpscaleMode.allCases))
    }

    @Test("Minimum RAM policy matches the catalog")
    func minimumRAMPolicy() {
        let requirements = Dictionary(uniqueKeysWithValues: ModelInfo.choices.map { ($0.id, $0.minimumRAMGB) })
        #expect(requirements["fast"] == 8)
        #expect(requirements["normal"] == 16)
        #expect(requirements["normal-hq"] == 16)
        #expect(requirements["advanced"] == 16)
        #expect(requirements["maximum"] == 24)
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
    }
}
