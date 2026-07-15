import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section("Preferences") {
                Text("Mode, size, and output format are saved automatically when you change them in the main window.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("CLI") {
                Text("The app uses VIVID_CLI when set, then ~/.local/bin/vvd.")
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 260)
    }
}
