import AppKit
import SwiftUI

struct SettingsView: View {
    private var modelDirectoryURL: URL {
        VividCLI.modelDirectoryURL()
    }

    var body: some View {
        Form {
            Section("Processing Options") {
                Text("Every launch starts from the recommended defaults, so a previous session's experimental settings never carry over to new photos.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Models") {
                LabeledContent("Location") {
                    Text(modelDirectoryURL.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([modelDirectoryURL])
                }
                .disabled(!FileManager.default.fileExists(atPath: modelDirectoryURL.path))
                Text("Set VIVID_HOME before launching to store the runtime and models elsewhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Command Line") {
                Text("Choose Vivid Upscaler > Install Command Line Tool… to run the same bundled CLI as vvd in Terminal, including batch processing with --output-dir.")
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 380)
    }
}
