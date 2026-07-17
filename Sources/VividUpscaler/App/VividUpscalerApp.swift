import AppKit
import SwiftUI

@main
struct VividUpscalerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = UpscaleStore()

    var body: some Scene {
        WindowGroup("Vivid Upscaler", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 760, minHeight: 560)
        }
        .defaultSize(width: 900, height: 650)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Install Command Line Tool…") {
                    Task { await store.installCommandLineTool() }
                }
            }
        }

        Window("Compare Images", id: "comparison-preview") {
            if let inputURL = store.inputURL,
               let outputURL = store.completedOutputURL {
                ComparisonPreviewView(originalURL: inputURL, upscaledURL: outputURL)
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
