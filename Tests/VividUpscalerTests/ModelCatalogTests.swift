import Testing
@testable import VividUpscaler

@Suite("Model catalog")
struct ModelCatalogTests {
    @Test("Catalog exposes every processing mode")
    func exposesEveryMode() {
        #expect(ModelInfo.choices.map(\.id) == ["fast", "normal", "normal-hq", "creative", "advanced", "maximum"])
        #expect(Set(ModelInfo.choices.map(\.mode)) == Set(UpscaleMode.allCases))
    }

    @Test("Minimum RAM policy matches the catalog")
    func minimumRAMPolicy() {
        let requirements = Dictionary(uniqueKeysWithValues: ModelInfo.choices.map { ($0.id, $0.minimumRAMGB) })
        #expect(requirements["fast"] == 8)
        #expect(requirements["normal"] == 16)
        #expect(requirements["normal-hq"] == 16)
        #expect(requirements["creative"] == 16)
        #expect(requirements["advanced"] == 16)
        #expect(requirements["maximum"] == 24)
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
