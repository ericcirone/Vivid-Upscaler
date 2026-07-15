import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class UpscaleStore {
    var inputURL: URL?
    var mode: UpscaleMode { didSet { defaults.set(mode.rawValue, forKey: "mode") } }
    var sizingKind: SizingKind { didSet { defaults.set(sizingKind.rawValue, forKey: "sizingKind") } }
    var scale: Double { didSet { defaults.set(scale, forKey: "scale") } }
    var resolution: Int { didSet { defaults.set(resolution, forKey: "resolution") } }
    var maxResolution: Int { didSet { defaults.set(maxResolution, forKey: "maxResolution") } }
    var format: OutputFormat { didSet { defaults.set(format.rawValue, forKey: "format") } }
    var isRunning = false
    var progress: Double?
    var status = "Drop a photo to begin"
    var errorMessage: String?
    var noticeMessage: String?
    var completedOutputURL: URL?
    var showOnboarding = false
    var installedModelIDs: Set<String> = []
    var pendingOverwriteURL: URL?

    private let cli = VividCLI()
    private let defaults = UserDefaults.standard

    init() {
        let defaults = UserDefaults.standard
        mode = UpscaleMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .normal
        sizingKind = SizingKind(rawValue: defaults.string(forKey: "sizingKind") ?? "") ?? .scale
        scale = defaults.object(forKey: "scale") == nil ? 2 : defaults.double(forKey: "scale")
        resolution = defaults.object(forKey: "resolution") == nil ? 2048 : defaults.integer(forKey: "resolution")
        maxResolution = defaults.object(forKey: "maxResolution") == nil ? 4096 : defaults.integer(forKey: "maxResolution")
        format = OutputFormat(rawValue: defaults.string(forKey: "format") ?? "") ?? .same
    }

    var options: UpscaleOptions {
        UpscaleOptions(mode: mode, sizingKind: sizingKind, scale: scale, resolution: resolution, maxResolution: maxResolution, format: format)
    }

    var outputURL: URL? {
        guard let inputURL else { return nil }
        return try? OutputNaming.validatedOutputURL(input: inputURL, options: options)
    }

    func refreshSetupState() async {
        do {
            installedModelIDs = try await cli.installedModels()
            showOnboarding = installedModelIDs.isEmpty
        } catch {
            errorMessage = error.localizedDescription
            showOnboarding = true
        }
    }

    func selectInput(_ url: URL) {
        guard url.isFileURL else { return }
        inputURL = url
        completedOutputURL = nil
        status = "Ready"
    }

    func chooseInput() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { selectInput(url) }
    }

    func requestUpscale() {
        let requiredModelID = mode == .advanced ? "advanced-3b" : mode.rawValue
        guard installedModelIDs.contains(requiredModelID) else {
            showOnboarding = true
            return
        }
        guard let outputURL else { return }
        if FileManager.default.fileExists(atPath: outputURL.path) {
            pendingOverwriteURL = outputURL
        } else {
            Task { await upscale(overwrite: false) }
        }
    }

    func upscale(overwrite: Bool) async {
        guard let inputURL else { return }
        do {
            let destination = try OutputNaming.validatedOutputURL(input: inputURL, options: options)
            if !overwrite, FileManager.default.fileExists(atPath: destination.path) {
                pendingOverwriteURL = destination
                return
            }
            isRunning = true
            progress = 0
            status = "Starting Vivid"
            errorMessage = nil
            completedOutputURL = nil
            try await cli.upscale(input: inputURL, output: destination, options: options) { [weak self] event in
                Task { @MainActor in
                    if let fraction = event.fraction { self?.progress = fraction }
                    self?.status = event.message
                }
            }
            progress = 1
            status = "Upscale complete"
            completedOutputURL = destination
        } catch {
            errorMessage = error.localizedDescription
            status = "Upscale failed"
        }
        isRunning = false
    }

    func cancel() {
        Task { await cli.cancel() }
        status = "Cancelling…"
    }

    func installModels(_ ids: [String]) async throws {
        try await cli.installModels(ids) { [weak self] event in
            Task { @MainActor in
                if let fraction = event.fraction, fraction >= (self?.progress ?? 0) { self?.progress = fraction }
                self?.status = event.message
            }
        }
        installedModelIDs = try await cli.installedModels()
    }

    func installCommandLineTool() async {
        do {
            let destination = try await cli.installCommandLineTool()
            noticeMessage = "Installed vvd at \(destination.path). It runs the CLI bundled inside this app."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revealOutput() {
        guard let completedOutputURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([completedOutputURL])
    }
}
