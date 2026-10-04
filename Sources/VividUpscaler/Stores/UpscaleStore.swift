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

    enum ExistingOutputPolicy {
        case replace
        case skip
    }

    struct OverwriteConfirmation: Identifiable {
        let id = UUID()
        let existingOutputs: [URL]
        let totalCount: Int
    }

    struct Comparison: Equatable {
        let original: URL
        let upscaled: URL
    }

    struct RunSummary: Equatable {
        var completed = 0
        var failed = 0
        var skipped = 0
        var cancelled = 0
        var elapsed: TimeInterval = 0
    }

    // MARK: Queue

    var items: [BatchItem] = []
    var selectedItemID: BatchItem.ID?
    /// Where results are written; `nil` saves each result beside its original.
    var outputDirectory: URL?

    // MARK: Options

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
    var hypirRestorationStrength: Double
    var hypirPatchSize: Int
    var hypirPatchStride: Int
    var hypirPrompt: String
    var noiseReduction: Double
    var sizingKind: SizingKind
    var scale: Double
    var resolution: Int
    var maxResolution: Int
    var format: OutputFormat
    var quality: Double

    // MARK: Processing state

    var isRunning = false
    var isCancelling = false
    /// Progress of the image currently being processed.
    var progress: Double?
    var status = "Add photos to begin"
    var logLines: [String] = []
    var elapsedTime: TimeInterval?
    var upscaleStartedAt: Date?
    var currentItemID: BatchItem.ID?
    var runItemIDs: [BatchItem.ID] = []
    var lastRunSummary: RunSummary?
    var errorMessage: String?
    var noticeMessage: String?
    var showOnboarding = false
    var pendingOverwrite: OverwriteConfirmation?
    var comparison: Comparison?
    var installedModelIDs: Set<String> = [] {
        didSet { normalizeModelSelections() }
    }

    private let cli = VividCLI()
    private var cancelRequested = false

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
        hypirRestorationStrength = 0.70
        hypirPatchSize = 768
        hypirPatchStride = 512
        hypirPrompt = HYPIRSettings.balancedPrompt
        noiseReduction = UpscaleOptions.defaultNoiseReduction
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
                customRestorationStrength: hypirRestorationStrength,
                customPatchSize: hypirPatchSize,
                customPatchStride: hypirPatchStride,
                customPrompt: hypirPrompt
            ),
            noiseReduction: noiseReduction,
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

    // MARK: Derived state

    var selectedItem: BatchItem? {
        items.first { $0.id == selectedItemID } ?? (items.count == 1 ? items.first : nil)
    }

    /// The image the options panel describes: the selection, else the first item.
    var inputURL: URL? {
        (selectedItem ?? items.first)?.url
    }

    var completedOutputURL: URL? {
        selectedItem?.outputURL
    }

    var completedOutputs: [URL] {
        items.compactMap(\.outputURL)
    }

    var currentItem: BatchItem? {
        items.first { $0.id == currentItemID }
    }

    var currentRunPosition: Int? {
        currentItemID.flatMap { runItemIDs.firstIndex(of: $0) }.map { $0 + 1 }
    }

    /// Fraction of the whole run, counting the active image's own progress.
    var overallProgress: Double? {
        guard !runItemIDs.isEmpty else { return nil }
        let finished = items.filter { runItemIDs.contains($0.id) && $0.status.isFinished }.count
        let current = currentItemID == nil ? 0 : (progress ?? 0)
        return min(1, (Double(finished) + current) / Double(runItemIDs.count))
    }

    var supportsOutputQuality: Bool {
        if items.isEmpty { return format.supportsQuality(for: nil) }
        return items.contains { format.supportsQuality(for: $0.url) }
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

    func outputURL(for item: BatchItem) -> URL? {
        try? OutputNaming.validatedOutputURL(input: item.url, options: options, directory: outputDirectory)
    }

    var outputURL: URL? {
        guard let item = selectedItem ?? items.first else { return nil }
        return outputURL(for: item)
    }

    func outputPixelSize(for item: BatchItem) -> CGSize? {
        item.pixelSize.flatMap(options.outputPixelSize(for:))
    }

    var outputLocationDescription: String {
        outputDirectory.map { FileManager.default.displayName(atPath: $0.path) } ?? "the same folder as each original"
    }

    // MARK: Models

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

    var hasInstalledUpscaleModel: Bool {
        ModelInfo.upscaleChoices.contains { installedModelIDs.contains($0.id) }
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

    func refreshSetupState() async {
        do {
            installedModelIDs = try await cli.installedModels()
            showOnboarding = !hasInstalledUpscaleModel
        } catch {
            errorMessage = error.localizedDescription
            showOnboarding = true
        }
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
        status = items.isEmpty ? "Add photos to begin" : "Ready"
    }

    func deleteModel(_ id: String) async throws {
        guard ModelInfo.info(for: id) != nil else { throw ModelError.unknownModel(id) }
        try await cli.deleteModel(id)
        installedModelIDs = try await cli.installedModels()
    }

    // MARK: Queue management

    func addInputs(_ urls: [URL]) {
        let discovered = InputDiscovery.imageURLs(from: urls)
        let existing = Set(items.map { $0.url.standardizedFileURL.path })
        var seen = existing
        let newItems = discovered.compactMap { url -> BatchItem? in
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted else { return nil }
            return BatchItem(url: url)
        }
        guard !newItems.isEmpty else {
            if discovered.isEmpty && !urls.isEmpty {
                errorMessage = "No supported images found. Vivid accepts PNG, JPEG, WebP, HEIC, AVIF, JPEG XL, TIFF, BMP, and GIF files."
            }
            return
        }
        items += newItems
        if selectedItemID == nil || items.count == newItems.count {
            selectedItemID = newItems.first?.id
        }
        if !isRunning { status = "Ready" }
        lastRunSummary = nil
        loadPixelSizes(for: newItems)
    }

    private func loadPixelSizes(for newItems: [BatchItem]) {
        let requests = newItems.map { ($0.id, $0.url) }
        Task.detached(priority: .utility) {
            for (id, url) in requests {
                let size = ImageInfo.orientedPixelSize(of: url)
                await MainActor.run {
                    if let index = self.items.firstIndex(where: { $0.id == id }) {
                        self.items[index].pixelSize = size
                    }
                }
            }
        }
    }

    func chooseInputs() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .folder]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = "Add"
        panel.message = "Choose photos or folders to upscale."
        if panel.runModal() == .OK { addInputs(panel.urls) }
    }

    func removeItems(_ ids: Set<BatchItem.ID>) {
        guard !ids.isEmpty else { return }
        let removable = ids.filter { $0 != currentItemID }
        items.removeAll { removable.contains($0.id) }
        if let selectedItemID, removable.contains(selectedItemID) {
            self.selectedItemID = items.first?.id
        }
        if items.isEmpty {
            status = "Add photos to begin"
            lastRunSummary = nil
        }
    }

    func removeAllItems() {
        guard !isRunning else { return }
        items.removeAll()
        selectedItemID = nil
        lastRunSummary = nil
        status = "Add photos to begin"
    }

    func removeFinishedItems() {
        removeItems(Set(items.filter { $0.outputURL != nil }.map(\.id)))
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose where upscaled images are saved."
        if let outputDirectory { panel.directoryURL = outputDirectory }
        if panel.runModal() == .OK, let url = panel.url { outputDirectory = url }
    }

    // MARK: Processing

    /// Validates the selected models, then starts processing or asks how to
    /// handle results that already exist.
    func requestUpscale() {
        guard !items.isEmpty, !isRunning else { return }
        guard mode.minimumRAMGB <= systemRAMGB else {
            errorMessage = "\(mode.title) requires at least \(mode.minimumRAMGB) GB of RAM. This Mac has \(systemRAMGB) GB."
            return
        }
        guard installedModelIDs.contains(mode.rawValue) else {
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
        if let outputDirectory, !FileManager.default.isWritableFile(atPath: outputDirectory.path) {
            errorMessage = "Vivid can't write to \(outputDirectory.path). Choose a different output folder."
            return
        }

        let outputs: [URL]
        do {
            outputs = try OutputNaming.uniqueOutputURLs(inputs: items.map(\.url), options: options, directory: outputDirectory)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        let existing = outputs.filter { FileManager.default.fileExists(atPath: $0.path) }
        if existing.isEmpty {
            startUpscale(policy: .replace)
        } else {
            pendingOverwrite = OverwriteConfirmation(existingOutputs: existing, totalCount: items.count)
        }
    }

    func startUpscale(policy: ExistingOutputPolicy) {
        pendingOverwrite = nil
        Task { await runQueue(policy: policy) }
    }

    func runQueue(policy: ExistingOutputPolicy) async {
        guard !isRunning, !items.isEmpty else { return }
        let runOptions = options
        let directory = outputDirectory
        let outputs: [URL]
        do {
            outputs = try OutputNaming.uniqueOutputURLs(inputs: items.map(\.url), options: runOptions, directory: directory)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        let plan = Array(zip(items.map(\.id), outputs))

        isRunning = true
        isCancelling = false
        cancelRequested = false
        errorMessage = nil
        lastRunSummary = nil
        logLines = []
        elapsedTime = nil
        runItemIDs = plan.map(\.0)
        for index in items.indices { items[index].status = .pending }
        let startedAt = Date()
        upscaleStartedAt = startedAt
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Upscaling images"
        )
        defer { ProcessInfo.processInfo.endActivity(activity) }

        var summary = RunSummary()
        var firstFailure: String?
        for (position, (id, destination)) in plan.enumerated() {
            guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
            updateDockBadge(remaining: plan.count - position)
            if cancelRequested {
                items[index].status = .cancelled
                summary.cancelled += 1
                continue
            }
            if policy == .skip, FileManager.default.fileExists(atPath: destination.path) {
                items[index].status = .skipped
                summary.skipped += 1
                logLines.append("Skipped \(items[index].url.lastPathComponent): \(destination.lastPathComponent) already exists")
                continue
            }

            currentItemID = id
            items[index].status = .processing
            progress = 0
            status = "Starting"
            if plan.count > 1 {
                logLines.append("— \(items[index].url.lastPathComponent) (\(position + 1) of \(plan.count)) —")
            }
            let itemStartedAt = Date()
            do {
                try await cli.upscale(input: items[index].url, output: destination, options: runOptions) { [weak self] event in
                    Task { @MainActor in
                        guard let self, self.currentItemID == id else { return }
                        if let fraction = event.fraction, fraction >= (self.progress ?? 0) {
                            self.progress = fraction
                        }
                        self.status = event.message
                        self.logLines.append(event.message)
                    }
                }
                if let current = items.firstIndex(where: { $0.id == id }) {
                    items[current].status = .completed(output: destination, elapsed: Date().timeIntervalSince(itemStartedAt))
                }
                summary.completed += 1
            } catch VividCLI.CLIError.cancelled {
                if let current = items.firstIndex(where: { $0.id == id }) {
                    items[current].status = .cancelled
                }
                summary.cancelled += 1
            } catch VividCLI.CLIError.failed(let message) {
                let description = VividCLI.CLIError.failed(message).localizedDescription
                if let current = items.firstIndex(where: { $0.id == id }) {
                    items[current].status = .failed(description)
                }
                firstFailure = firstFailure ?? description
                summary.failed += 1
                logLines.append("Failed: \(description)")
            } catch {
                // Missing runtime or bundle resources affect every image equally.
                if let current = items.firstIndex(where: { $0.id == id }) {
                    items[current].status = .failed(error.localizedDescription)
                }
                summary.failed += 1
                errorMessage = error.localizedDescription
                cancelRequested = true
            }
            currentItemID = nil
        }

        summary.elapsed = Date().timeIntervalSince(startedAt)
        elapsedTime = summary.elapsed
        lastRunSummary = summary
        progress = nil
        currentItemID = nil
        isRunning = false
        isCancelling = false
        upscaleStartedAt = nil
        updateDockBadge(remaining: 0)
        status = Self.describe(summary)
        logLines.append("\(status) in \(Self.formatElapsedTime(summary.elapsed))")

        if plan.count == 1, let firstFailure, errorMessage == nil {
            errorMessage = firstFailure
        }
        if let completedID = plan.map(\.0).first(where: { id in items.contains { $0.id == id && $0.outputURL != nil } }),
           selectedItem?.outputURL == nil {
            selectedItemID = completedID
        }
        if let app = NSApp, !app.isActive {
            app.requestUserAttention(.informationalRequest)
        }
    }

    static func describe(_ summary: RunSummary) -> String {
        var parts: [String] = []
        let total = summary.completed + summary.failed + summary.skipped + summary.cancelled
        if summary.completed > 0 {
            parts.append(total == 1 ? "Upscale complete" : "\(summary.completed) upscaled")
        }
        if summary.skipped > 0 { parts.append("\(summary.skipped) skipped") }
        if summary.failed > 0 { parts.append(total == 1 ? "Upscale failed" : "\(summary.failed) failed") }
        if summary.cancelled > 0 { parts.append(total == 1 ? "Cancelled" : "\(summary.cancelled) cancelled") }
        return parts.isEmpty ? "Nothing to upscale" : parts.joined(separator: " · ")
    }

    func cancel() {
        guard isRunning else { return }
        cancelRequested = true
        isCancelling = true
        status = "Cancelling…"
        Task { await cli.cancel() }
    }

    private func updateDockBadge(remaining: Int) {
        NSApp?.dockTile.badgeLabel = remaining > 1 ? "\(remaining)" : nil
    }

    // MARK: Results

    func revealOutputs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func revealOutput() {
        if let completedOutputURL {
            revealOutputs([completedOutputURL])
        } else {
            revealOutputs(completedOutputs)
        }
    }

    /// Prepares the comparison window for `item`; returns false if it has no result yet.
    @discardableResult
    func prepareComparison(for item: BatchItem) -> Bool {
        guard let output = item.outputURL else { return false }
        comparison = Comparison(original: item.url, upscaled: output)
        return true
    }

    func installCommandLineTool() async {
        do {
            let destination = try await cli.installCommandLineTool()
            noticeMessage = "Installed vvd at \(destination.path). It runs the CLI bundled inside this app."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
