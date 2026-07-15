import SwiftUI

struct SettingsView: View {
    private var modelDirectoryURL: URL {
        VividCLI.modelDirectoryURL()
    }

    var body: some View {
        Form {
            Section("Preferences") {
                Text("Mode, size, and output format are saved automatically when you change them in the main window.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Models") {
                Text("Model files are stored at:")
                    .font(.callout)
                Text(modelDirectoryURL.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Section("CLI") {
                Text("Vivid Upscaler runs its bundled CLI. Choose Vivid Upscaler > Install Command Line Tool… to make the same CLI available as vvd in Terminal.")
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 340)
    }
}
