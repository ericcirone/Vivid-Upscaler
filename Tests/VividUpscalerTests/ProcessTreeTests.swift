import Foundation
import Testing
@testable import VividUpscaler

@Suite("Process tree cancellation")
struct ProcessTreeTests {
    @Test("Cancelling stops grandchildren, not just the wrapper")
    func terminatesDescendants() async throws {
        let wrapper = Process()
        wrapper.executableURL = URL(fileURLWithPath: "/bin/sh")
        // The shell waits on a child that itself waits on a grandchild, like
        // vvd -> python -> worker.
        wrapper.arguments = ["-c", "/bin/sh -c 'sleep 60 & wait' & wait"]
        try wrapper.run()
        try await Task.sleep(for: .milliseconds(300))

        let descendants = VividCLI.descendantProcessIdentifiers(of: wrapper.processIdentifier)
        #expect(descendants.count >= 2)

        VividCLI.terminateProcessTree(rootedAt: wrapper.processIdentifier)
        wrapper.waitUntilExit()
        try await Task.sleep(for: .milliseconds(300))

        for pid in descendants {
            #expect(kill(pid, 0) != 0, "process \(pid) survived cancellation")
        }
    }
}
