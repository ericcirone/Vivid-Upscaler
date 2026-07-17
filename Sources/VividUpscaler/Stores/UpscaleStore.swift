import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class UpscaleStore {
    enum ModelError: LocalizedError {
        case unknownModel(String)
        case insufficientRAM(model: String, requiredGB: Int, availableGB: Int)

        var errorDescription: String? {
            switch self {
            case .unknownModel(let id): "Unknown model: \(id)."
            case .insufficientRAM(let model, let requiredGB, let availableGB):
                "\(model) requires at least \(requiredGB) GB of RAM. This Mac has \(availableGB) GB."
            }
        }
    }

    var inputURL: URL?
    var mode: UpscaleMode { didSet { defaults.set(mode.rawValue, forKey: "mode") } }
    var deblurMode: DeblurMode { didSet { defaults.set(deblurMode.rawValue, forKey: "deblurMode") } }
    var variationSeed: Int { didSet { defaults.set(variationSeed, forKey: "variationSeed") } }
    var seedVR2Preset: SeedVR2Preset { didSet { defaults.set(seedVR2Preset.rawValue, forKey: "seedVR2Preset") } }
    var seedVR2InputNoiseScale: Double { didSet { defaults.set(seedVR2InputNoiseScale, forKey: "seedVR2InputNoiseScale") } }
    var seedVR2LatentNoiseScale: Double { didSet { defaults.set(seedVR2LatentNoiseScale, forKey: "seedVR2LatentNoiseScale") } }
    var seedVR2ColorCorrection: SeedVR2ColorCorrection { didSet { defaults.set(seedVR2ColorCorrection.rawValue, forKey: "seedVR2ColorCorrection") } }
    var sizingKind: SizingKind { didSet { defaults.set(sizingKind.rawValue, forKey: "sizingKind") } }
    var scale: Double { didSet { defaults.set(scale, forKey: "scale") } }
    var resolution: Int { didSet { defaults.set(resolution, forKey: "resolution") } }
    var maxResolution: Int { didSet { defaults.set(maxResolution, forKey: "maxResolution") } }
    var format: OutputFormat { didSet { defaults.set(format.rawValue, forKey: "format") } }
    var quality: Double { didSet { defaults.set(quality, forKey: "quality") } }
    var isRunning = false
    var progress: Double?
    var status = "Drop a photo to begin"
    var logLines: [String] = []
    var elapsedTime: TimeInterval?
    var upscaleStartedAt: Date?
    var errorMessage: String?
    var noticeMessage: String?
    var completedOutputURL: URL?
    var showOnboarding = false
    var installedModelIDs: Set<String> = [] {
        didSet { normalizeModelSelections() }
    }
    var pendingOverwriteURL: URL?

    private let cli = VividCLI()
    private let defaults = UserDefaults.standard

    let systemRAMGB: Int

    init(systemMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory) {
        let defaults = UserDefaults.standard
        systemRAMGB = Int(systemMemoryBytes / 1_073_741_824)
        let savedModeID = defaults.string(forKey: "mode") ?? ""
        let migratedModeID = savedModeID == "advanced-experimental" ? "maximum-experimental" : savedModeID
        let savedMode = UpscaleMode(rawValue: migratedModeID) ?? .normal
        if savedModeID != migratedModeID {
            defaults.set(migratedModeID, forKey: "mode")
        }
        mode = savedMode.minimumRAMGB <= systemRAMGB ? savedMode : (systemRAMGB >= 16 ? .normal : .fast)
        let savedDeblurMode = DeblurMode(rawValue: defaults.string(forKey: "deblurMode") ?? "") ?? .none
        deblurMode = savedDeblurMode.minimumRAMGB <= systemRAMGB ? savedDeblurMode : .none
        variationSeed = defaults.object(forKey: "variationSeed") == nil
            ? GenerativeOptions.defaultVariationSeed
            : defaults.integer(forKey: "variationSeed")
        seedVR2Preset = SeedVR2Preset(rawValue: defaults.string(forKey: "seedVR2Preset") ?? "") ?? .faithful
        seedVR2InputNoiseScale = defaults.object(forKey: "seedVR2InputNoiseScale") == nil ? 0 : defaults.double(forKey: "seedVR2InputNoiseScale")
        seedVR2LatentNoiseScale = defaults.object(forKey: "seedVR2LatentNoiseScale") == nil ? 0 : defaults.double(forKey: "seedVR2LatentNoiseScale")
        seedVR2ColorCorrection = SeedVR2ColorCorrection(rawValue: defaults.string(forKey: "seedVR2ColorCorrection") ?? "") ?? .lab
        sizingKind = SizingKind(rawValue: defaults.string(forKey: "sizingKind") ?? "") ?? .scale
        scale = defaults.object(forKey: "scale") == nil ? 2 : defaults.double(forKey: "scale")
        resolution = defaults.object(forKey: "resolution") == nil ? 2048 : defaults.integer(forKey: "resolution")
        maxResolution = defaults.object(forKey: "maxResolution") == nil ? 4096 : defaults.integer(forKey: "maxResolution")
        format = OutputFormat(rawValue: defaults.string(forKey: "format") ?? "") ?? .same
        let savedQuality = defaults.object(forKey: "quality") == nil ? 90 : defaults.double(forKey: "quality")
        quality = Double(OutputQualityPreset.nearest(to: savedQuality).rawValue)
    }

    var options: UpscaleOptions {
        UpscaleOptions(
            mode: mode,
            deblurMode: deblurMode,
            generativeOptions: .init(variationSeed: variationSeed),
            seedVR2Options: .init(
                preset: seedVR2Preset,
                customInputNoiseScale: seedVR2InputNoiseScale,
                customLatentNoiseScale: seedVR2LatentNoiseScale,
                customColorCorrection: seedVR2ColorCorrection
            ),
            sizingKind: sizingKind,
            scale: scale,
            resolution: resolution,
            maxResolution: maxResolution,
            format: format,
            quality: quality
        )
    }

    func tryAnotherVariation() {
        variationSeed = Int.random(in: 0...Int(Int32.max))
    }

    var supportsOutputQuality: Bool {
        format.supportsQuality(for: inputURL)
    }

    var fullLog: String {
        logLines.joined(separator: "\n")
    }

    var formattedElapsedTime: String? {
        elapsedTime.map(Self.formatElapsedTime)
    }

    func formattedRunningElapsedTime(at date: Date) -> String {
        guard let upscaleStartedAt else { return Self.formatElapsedTime(0) }
        return Self.formatElapsedTime(date.timeIntervalSince(upscaleStartedAt))
    }

    static func formatElapsedTime(_ elapsedTime: TimeInterval) -> String {
        let totalSeconds = max(0, Int(elapsedTime.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    func canInstall(_ model: ModelInfo) -> Bool {
        model.isCompatible(withRAMGB: systemRAMGB)
    }

    func isInstalled(_ model: ModelInfo) -> Bool {
        installedModelIDs.contains(model.id)
    }

    var installedUpscaleModes: [UpscaleMode] {
        UpscaleMode.allCases.filter { installedModelIDs.contains($0.rawValue) }
    }

    var installedDeblurModes: [DeblurMode] {
        [.none] + DeblurMode.allCases.filter {
            $0 != .none && installedModelIDs.contains($0.rawValue)
        }
    }

    private func normalizeModelSelections() {
        if !installedModelIDs.contains(mode.rawValue),
           let fallback = installedUpscaleModes.first(where: { $0.minimumRAMGB <= systemRAMGB })
                ?? installedUpscaleModes.first {
            mode = fallback
        }

        if let deblurModelID = deblurMode.modelID,
           !installedModelIDs.contains(deblurModelID) {
            deblurMode = .none
        }
    }

    var outputURL: URL? {
        guard let inputURL else { return nil }
        return try? OutputNaming.validatedOutputURL(input: inputURL, options: options)
    }

    func refreshSetupState() async {
        do {
            installedModelIDs = try await cli.installedModels()
            showOnboarding = !hasInstalledUpscaleModel
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
        let requiredModelID = mode.rawValue
        guard mode.minimumRAMGB <= systemRAMGB else {
            errorMessage = "\(mode.title) requires at least \(mode.minimumRAMGB) GB of RAM. This Mac has \(systemRAMGB) GB."
            return
        }
        guard installedModelIDs.contains(requiredModelID) else {
            showOnboarding = true
            return
        }
        if let deblurModelID = deblurMode.modelID {
            guard deblurMode.minimumRAMGB <= systemRAMGB else {
                errorMessage = "\(deblurMode.title) requires at least \(deblurMode.minimumRAMGB) GB of RAM. This Mac has \(systemRAMGB) GB."
                return
            }
            guard installedModelIDs.contains(deblurModelID) else {
                showOnboarding = true
                return
            }
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
            logLines = [status]
            elapsedTime = nil
            errorMessage = nil
            completedOutputURL = nil
            let startedAt = Date()
            upscaleStartedAt = startedAt
            try await cli.upscale(input: inputURL, output: destination, options: options) { [weak self] event in
                Task { @MainActor in
                    if let fraction = event.fraction { self?.progress = fraction }
                    self?.status = event.message
                    self?.logLines.append(event.message)
                }
            }
            elapsedTime = Date().timeIntervalSince(startedAt)
            progress = 1
            status = "Upscale complete"
            if let formattedElapsedTime {
                logLines.append("Total elapsed: \(formattedElapsedTime)")
            }
            completedOutputURL = destination
        } catch {
            errorMessage = error.localizedDescription
            status = "Upscale failed"
        }
        isRunning = false
        upscaleStartedAt = nil
    }

    func cancel() {
        Task { await cli.cancel() }
        status = "Cancelling…"
    }

    func installModels(_ ids: [String]) async throws {
        for id in ids {
            guard let model = ModelInfo.info(for: id) else { throw ModelError.unknownModel(id) }
            guard canInstall(model) else {
                throw ModelError.insufficientRAM(model: model.title, requiredGB: model.minimumRAMGB, availableGB: systemRAMGB)
            }
        }
        try await cli.installModels(ids) { [weak self] event in
            Task { @MainActor in
                if let fraction = event.fraction, fraction >= (self?.progress ?? 0) { self?.progress = fraction }
                self?.status = event.message
            }
        }
        installedModelIDs = try await cli.installedModels()
    }

    func deleteModel(_ id: String) async throws {
        guard ModelInfo.info(for: id) != nil else { throw ModelError.unknownModel(id) }
        try await cli.deleteModel(id)
        installedModelIDs = try await cli.installedModels()
    }

    var hasInstalledUpscaleModel: Bool {
        ModelInfo.upscaleChoices.contains { installedModelIDs.contains($0.id) }
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
