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
