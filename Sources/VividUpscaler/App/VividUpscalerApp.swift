import AppKit
import SwiftUI

@main
struct VividUpscalerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = UpscaleStore()

    var body: some Scene {
        // A single-instance window: photos opened from Finder join the one
        // queue instead of SwiftUI creating a new window per open event.
        Window("Vivid Upscaler", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 780, minHeight: 560)
                .onAppear { appDelegate.attach(store) }
        }
        .defaultSize(width: 1_040, height: 700)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Install Command Line Tool…") {
                    Task { await store.installCommandLineTool() }
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("Add Photos…") { store.chooseInputs() }
                    .keyboardShortcut("o")
            }
            CommandMenu("Upscale") {
                Button(store.items.count > 1 ? "Upscale \(store.items.count) Photos" : "Upscale Photo") {
                    store.requestUpscale()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(store.items.isEmpty || store.isRunning)

                Button("Stop") { store.cancel() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!store.isRunning)

                Divider()

                Button("Choose Output Folder…") { store.chooseOutputDirectory() }
                Button("Save Beside Originals") { store.outputDirectory = nil }
                    .disabled(store.outputDirectory == nil)

                Divider()

                Button("Show Results in Finder") { store.revealOutputs(store.completedOutputs) }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(store.completedOutputs.isEmpty)
                Button("Remove Finished Photos") { store.removeFinishedItems() }
                    .disabled(store.completedOutputs.isEmpty)
                Button("Remove All Photos") { store.removeAllItems() }
                    .keyboardShortcut(.delete, modifiers: [.command, .shift])
                    .disabled(store.items.isEmpty || store.isRunning)

                Divider()

                Button("Manage Models…") { store.showOnboarding = true }
                    .disabled(store.isRunning)
            }
        }

        Window("Compare", id: "comparison-preview") {
            if let comparison = store.comparison {
                ComparisonPreviewView(originalURL: comparison.original, upscaledURL: comparison.upscaled)
            } else {
                ContentUnavailableView(
                    "Preview Unavailable",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text("Complete an upscale before opening the preview.")
                )
                .frame(minWidth: 760, minHeight: 560)
            }
        }
        .defaultSize(width: 1_000, height: 720)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var store: UpscaleStore?
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func attach(_ store: UpscaleStore) {
        self.store = store
        if !pendingURLs.isEmpty {
            store.addInputs(pendingURLs)
            pendingURLs.removeAll()
        }
    }

    /// Photos opened from Finder or dropped on the Dock icon join the queue.
    func application(_ application: NSApplication, open urls: [URL]) {
        if let store {
            store.addInputs(urls)
        } else {
            pendingURLs += urls
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard store?.isRunning == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Stop upscaling and quit?"
        alert.informativeText = "The current photo will not be saved. Finished results are kept."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        VividCLI.terminateActiveProcessTree()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
