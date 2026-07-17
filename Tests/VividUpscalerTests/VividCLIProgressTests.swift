import Testing
@testable import VividUpscaler

@Suite("CLI progress events")
struct VividCLIProgressTests {
    @Test("Machine-readable runtime progress reaches the app")
    func runtimeProgress() {
        let event = VividCLI.event(for: "[progress] 72% Decoding image")

        #expect(event.fraction == 0.72)
        #expect(event.message == "Decoding image")
    }

    @Test("The processing stage advances beyond preparation")
    func processingStage() {
        let event = VividCLI.event(for: "[2/3] Upscaling")

        #expect(event.fraction == 0.15)
        #expect(event.message == "Upscaling image")
    }
}
