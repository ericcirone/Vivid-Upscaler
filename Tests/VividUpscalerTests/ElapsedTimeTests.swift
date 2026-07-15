import Foundation
import Testing
@testable import VividUpscaler

@Suite("Elapsed time formatting")
struct ElapsedTimeTests {
    @Test("Formats seconds as hours, minutes, and seconds")
    @MainActor
    func formatsElapsedTime() {
        #expect(UpscaleStore.formatElapsedTime(0) == "00:00:00")
        #expect(UpscaleStore.formatElapsedTime(65.9) == "00:01:05")
        #expect(UpscaleStore.formatElapsedTime(3_661) == "01:01:01")
    }

    @Test("Formats elapsed time while an upscale is running")
    @MainActor
    func formatsRunningElapsedTime() {
        let store = UpscaleStore()
        store.upscaleStartedAt = Date(timeIntervalSince1970: 100)

        #expect(store.formattedRunningElapsedTime(at: Date(timeIntervalSince1970: 165.9)) == "00:01:05")
    }
}
