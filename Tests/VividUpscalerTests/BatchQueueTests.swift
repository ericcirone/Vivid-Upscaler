import Foundation
import Testing
@testable import VividUpscaler

@Suite("Batch queue")
struct BatchQueueTests {
    private func makeFolder(_ files: [String]) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("vivid-batch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for file in files {
            let url = folder.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
        return folder
    }

    @Test("Folders contribute their supported top-level images in Finder order")
    func discoversFolderImages() throws {
        let folder = try makeFolder([
            "IMG_10.HEIC", "IMG_2.jpg", "notes.txt", ".hidden.png",
            "IMG_2-vivid-upscale-normal-2x.jpg", "nested/deep.png"
        ])
        defer { try? FileManager.default.removeItem(at: folder) }

        let names = InputDiscovery.imageURLs(from: [folder]).map(\.lastPathComponent)
        #expect(names == ["IMG_2.jpg", "IMG_10.HEIC"])
    }

    @Test("Adding inputs skips duplicates and selects the first new photo")
    @MainActor
    func addingInputsDeduplicates() throws {
        let folder = try makeFolder(["a.png", "b.jpg"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = UpscaleStore(systemMemoryBytes: 32 * 1_073_741_824)

        store.addInputs([folder.appendingPathComponent("a.png")])
        store.addInputs([folder])

        #expect(store.items.map(\.url.lastPathComponent) == ["a.png", "b.jpg"])
        #expect(store.selectedItem?.url.lastPathComponent == "a.png")

        store.removeItems([store.items[0].id])
        #expect(store.items.map(\.url.lastPathComponent) == ["b.jpg"])
        #expect(store.selectedItem?.url.lastPathComponent == "b.jpg")
    }

    @Test("Unsupported drops explain which formats work")
    @MainActor
    func unsupportedInputsReportAnError() throws {
        let folder = try makeFolder(["readme.txt"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = UpscaleStore(systemMemoryBytes: 32 * 1_073_741_824)

        store.addInputs([folder.appendingPathComponent("readme.txt")])

        #expect(store.items.isEmpty)
        #expect(store.errorMessage?.contains("HEIC") == true)
    }

    @Test("Run summaries read naturally for single photos and batches")
    @MainActor
    func summaries() {
        #expect(UpscaleStore.describe(.init(completed: 1)) == "Upscale complete")
        #expect(UpscaleStore.describe(.init(failed: 1)) == "Upscale failed")
        #expect(UpscaleStore.describe(.init(completed: 8, failed: 1, skipped: 2)) == "8 upscaled · 2 skipped · 1 failed")
        #expect(UpscaleStore.describe(.init(completed: 3, cancelled: 4)) == "3 upscaled · 4 cancelled")
    }

    @Test("Overall progress counts finished photos and the active photo")
    @MainActor
    func overallProgress() {
        let store = UpscaleStore(systemMemoryBytes: 32 * 1_073_741_824)
        store.items = [
            BatchItem(url: URL(fileURLWithPath: "/tmp/1.png"), status: .completed(output: URL(fileURLWithPath: "/tmp/1-out.png"), elapsed: 1)),
            BatchItem(url: URL(fileURLWithPath: "/tmp/2.png"), status: .processing),
            BatchItem(url: URL(fileURLWithPath: "/tmp/3.png")),
            BatchItem(url: URL(fileURLWithPath: "/tmp/4.png"))
        ]
        store.runItemIDs = store.items.map(\.id)
        store.currentItemID = store.items[1].id
        store.progress = 0.5

        #expect(store.overallProgress == 0.375)
        #expect(store.currentRunPosition == 2)
    }
}
