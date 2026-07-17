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
    var mode: UpscaleMode
    var deblurMode: DeblurMode
    var faceRestoreEnabled: Bool
    var codeFormerPreset: CodeFormerPreset
    var codeFormerFidelityWeight: Double
    var variationSeed: Int
    var seedVR2Preset: SeedVR2Preset
    var seedVR2InputNoiseScale: Double
    var seedVR2LatentNoiseScale: Double
    var seedVR2ColorCorrection: SeedVR2ColorCorrection
    var hypirPreset: HYPIRPreset
    var hypirPatchSize: Int
    var hypirPatchStride: Int
    var hypirPrompt: String
    var sizingKind: SizingKind
    var scale: Double
    var resolution: Int
    var maxResolution: Int
    var format: OutputFormat
    var quality: Double
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

    let systemRAMGB: Int

    init(systemMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory) {
        systemRAMGB = Int(systemMemoryBytes / 1_073_741_824)
        mode = systemRAMGB >= 16 ? .normal : .fast
        deblurMode = .none
        faceRestoreEnabled = false
        codeFormerPreset = .balanced
        codeFormerFidelityWeight = 0.7
        variationSeed = GenerativeOptions.defaultVariationSeed
        seedVR2Preset = .faithful
        seedVR2InputNoiseScale = 0
        seedVR2LatentNoiseScale = 0
        seedVR2ColorCorrection = .lab
        hypirPreset = .balanced
        hypirPatchSize = 768
        hypirPatchStride = 512
        hypirPrompt = HYPIRSettings.balancedPrompt
        sizingKind = .scale
        scale = 2
        resolution = 2048
        maxResolution = 4096
        format = .same
        quality = Double(OutputQualityPreset.high.rawValue)
    }

    var options: UpscaleOptions {
        UpscaleOptions(
            mode: mode,
            deblurMode: deblurMode,
            codeFormerOptions: .init(
                isEnabled: faceRestoreEnabled,
                preset: codeFormerPreset,
                customFidelityWeight: codeFormerFidelityWeight
            ),
            generativeOptions: .init(variationSeed: variationSeed),
            seedVR2Options: .init(
                preset: seedVR2Preset,
                customInputNoiseScale: seedVR2InputNoiseScale,
                customLatentNoiseScale: seedVR2LatentNoiseScale,
                customColorCorrection: seedVR2ColorCorrection
            ),
            hypirOptions: .init(
                preset: hypirPreset,
                customPatchSize: hypirPatchSize,
                customPatchStride: hypirPatchStride,
                customPrompt: hypirPrompt
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

    var isFaceRestoreInstalled: Bool {
        installedModelIDs.contains("face-restore")
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
        if faceRestoreEnabled && !isFaceRestoreInstalled {
            faceRestoreEnabled = false
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
        if faceRestoreEnabled {
            guard systemRAMGB >= 8 else {
                errorMessage = "Face Restore requires at least 8 GB of RAM. This Mac has \(systemRAMGB) GB."
                return
            }
            guard isFaceRestoreInstalled else {
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
                    if let fraction = event.fraction, fraction >= (self?.progress ?? 0) {
                        self?.progress = fraction
                    }
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
