import Foundation
import Testing
@testable import VividUpscaler

@Suite("Model directory")
struct ModelDirectoryTests {
    @Test("Uses the default runtime directory")
    func defaultDirectory() {
        let homeDirectory = URL(fileURLWithPath: "/Users/example", isDirectory: true)

        let result = VividCLI.modelDirectoryURL(environment: [:], homeDirectory: homeDirectory)

        #expect(result.path == "/Users/example/.local/share/vivid/models")
    }

    @Test("Respects a custom VIVID_HOME")
    func customDirectory() {
        let homeDirectory = URL(fileURLWithPath: "/Users/example", isDirectory: true)

        let result = VividCLI.modelDirectoryURL(
            environment: ["VIVID_HOME": "/Volumes/Models/vivid"],
            homeDirectory: homeDirectory
        )

        #expect(result.path == "/Volumes/Models/vivid/models")
    }
}
