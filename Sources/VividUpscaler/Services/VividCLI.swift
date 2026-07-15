import Foundation

actor VividCLI {
    struct Event: Sendable {
        let fraction: Double?
        let message: String
    }

    enum CLIError: LocalizedError {
        case notInstalled
        case bundledResourcesMissing
        case appTranslocated
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                "Vivid's processing runtime could not be installed."
            case .bundledResourcesMissing:
                "This copy of Vivid Upscaler does not contain its bundled CLI resources."
            case .appTranslocated:
                "Move Vivid Upscaler to Applications before installing its command line tool."
            case .failed(let message):
                message.isEmpty ? "Vivid CLI failed." : message
            }
        }
    }

    private var process: Process?

    static func modelDirectoryURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        runtimeRootURL(environment: environment, homeDirectory: homeDirectory)
            .appendingPathComponent("models", isDirectory: true)
    }

    func executableURL() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        var candidates: [String] = []
        if let bundled = bundledResource(named: "vvd") {
            candidates.append(bundled.path)
        }
        if let explicit = environment["VIVID_CLI"], !explicit.isEmpty {
            candidates.append(explicit)
        }
        candidates += [
            NSString(string: "~/.local/bin/vvd").expandingTildeInPath,
            "/opt/homebrew/bin/vvd",
            "/usr/local/bin/vvd"
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map(URL.init(fileURLWithPath:))
    }

    func installedModels() async throws -> Set<String> {
        let output = try await runForOutput(arguments: ["models", "status", "--json"])
        guard let data = output.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Bool] else {
            throw CLIError.failed("The CLI returned an invalid model status response.")
        }
        return Set(object.compactMap { $0.value ? $0.key : nil })
    }

    func installModels(_ ids: [String], onEvent: @escaping @Sendable (Event) -> Void) async throws {
        try await ensureRuntime(onEvent: onEvent)
        for (index, id) in ids.enumerated() {
            let base = Double(index) / Double(max(ids.count, 1))
            let span = 1.0 / Double(max(ids.count, 1))
            try await run(arguments: ["models", "install", id]) { line in
                let local = Self.percentage(in: line)
                onEvent(Event(fraction: local.map { base + ($0 * span) }, message: line))
            }
        }
    }

    func deleteModel(_ id: String) async throws {
        _ = try await runForOutput(arguments: ["models", "delete", id])
    }

    func upscale(
        input: URL,
        output: URL,
        options: UpscaleOptions,
        onEvent: @escaping @Sendable (Event) -> Void
    ) async throws {
        try await ensureRuntime(onEvent: onEvent)
        var arguments = [input.path, output.path, "--mode", options.mode.rawValue]
        switch options.sizingKind {
        case .scale:
            arguments += ["--scale", String(options.scale)]
        case .resolution:
            arguments += ["--resolution", String(options.resolution), "--max-resolution", String(options.maxResolution)]
        }
        if options.format.supportsQuality(for: input) {
            arguments += ["--quality", String(Int(options.quality.rounded()))]
        }

        try await run(arguments: arguments) { line in
            onEvent(Self.event(for: line))
        }
    }

    func cancel() {
        process?.terminate()
    }

    func installCommandLineTool() throws -> URL {
        guard let executable = bundledResource(named: "vvd") else {
            throw CLIError.bundledResourcesMissing
        }
        let isReadOnlyVolume = (try? executable.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) == true
        if executable.path.contains("/AppTranslocation/") || isReadOnlyVolume {
            throw CLIError.appTranslocated
        }

        let binDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin", isDirectory: true)
        let destination = binDirectory.appendingPathComponent("vvd")
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: destination.path)
            || (try? FileManager.default.destinationOfSymbolicLink(atPath: destination.path)) != nil {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: executable)
        return destination
    }

    private func bundledResource(named name: String) -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let url = resourceURL.appendingPathComponent("CLI", isDirectory: true).appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func runtimeRoot() -> URL {
        Self.runtimeRootURL(
            environment: ProcessInfo.processInfo.environment,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    private static func runtimeRootURL(environment: [String: String], homeDirectory: URL) -> URL {
        if let explicit = environment["VIVID_HOME"], !explicit.isEmpty {
            return URL(fileURLWithPath: NSString(string: explicit).expandingTildeInPath, isDirectory: true)
        }
        return homeDirectory
            .appendingPathComponent(".local/share/vivid", isDirectory: true)
    }

    private func runtimeIsInstalled() -> Bool {
        let root = runtimeRoot()
        let versionURL = root.appendingPathComponent("runtime-version")
        let version = try? String(contentsOf: versionURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        return FileManager.default.isExecutableFile(atPath: root.appendingPathComponent("venv/bin/python").path)
            && FileManager.default.fileExists(atPath: root.appendingPathComponent("repo/inference_cli.py").path)
            && version == "10"
    }

    private func ensureRuntime(onEvent: @escaping @Sendable (Event) -> Void) async throws {
        guard !runtimeIsInstalled() else { return }
        guard let installer = bundledResource(named: "install.sh") else {
            throw CLIError.bundledResourcesMissing
        }

        onEvent(Event(fraction: nil, message: "Installing Vivid processing runtime"))
        let privateBin = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VividUpscaler/InternalCLI", isDirectory: true)
        try await run(
            executable: installer,
            arguments: [],
            environmentOverrides: ["VIVID_BIN_DIR": privateBin.path]
        ) { line in
            onEvent(Event(fraction: Self.percentage(in: line), message: line))
        }
        guard runtimeIsInstalled() else { throw CLIError.notInstalled }
    }

    private func runForOutput(arguments: [String]) async throws -> String {
        final class Collector: @unchecked Sendable {
            private let lock = NSLock()
            private var values: [String] = []

            func append(_ value: String) {
                lock.lock()
                values.append(value)
                lock.unlock()
            }

            func joined() -> String {
                lock.lock()
                defer { lock.unlock() }
                return values.joined(separator: "\n")
            }
        }
        let collector = Collector()
        try await run(arguments: arguments) { collector.append($0) }
        return collector.joined()
    }

    private func run(arguments: [String], onLine: @escaping @Sendable (String) -> Void) async throws {
        guard let executable = executableURL() else { throw CLIError.notInstalled }

        try await run(executable: executable, arguments: arguments, environmentOverrides: [:], onLine: onLine)
    }

    private func run(
        executable: URL,
        arguments: [String],
        environmentOverrides: [String: String],
        onLine: @escaping @Sendable (String) -> Void
    ) async throws {

        let task = Process()
        let pipe = Pipe()
        task.executableURL = executable
        task.arguments = arguments
        task.environment = ProcessInfo.processInfo.environment.merging(environmentOverrides) { _, override in override }
        task.standardOutput = pipe
        task.standardError = pipe
        process = task

        final class LineBuffer: @unchecked Sendable {
            private let lock = NSLock()
            private var data = Data()
            private(set) var lines: [String] = []

            func append(_ chunk: Data, emit: (String) -> Void) {
                lock.lock()
                defer { lock.unlock() }
                data.append(chunk)
                while let newline = data.firstIndex(of: 10) {
                    let lineData = data[..<newline]
                    data.removeSubrange(...newline)
                    if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                        lines.append(line)
                        emit(line)
                    }
                }
            }

            func flush(emit: (String) -> Void) {
                lock.lock()
                defer { lock.unlock() }
                if let line = String(data: data, encoding: .utf8), !line.isEmpty {
                    lines.append(line)
                    emit(line)
                }
                data.removeAll()
            }
        }

        let buffer = LineBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { buffer.append(data, emit: onLine) }
        }

        do {
            try task.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            process = nil
            throw error
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            task.terminationHandler = { _ in continuation.resume() }
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        buffer.append(pipe.fileHandleForReading.readDataToEndOfFile(), emit: onLine)
        buffer.flush(emit: onLine)
        process = nil

        guard task.terminationStatus == 0 else {
            throw CLIError.failed(buffer.lines.suffix(8).joined(separator: "\n"))
        }
    }

    nonisolated private static func percentage(in line: String) -> Double? {
        let pattern = #"([0-9]{1,3})(?:\.[0-9]+)?%"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line),
              let value = Double(line[range]) else { return nil }
        return min(max(value / 100, 0), 1)
    }

    nonisolated private static func event(for line: String) -> Event {
        if line.contains("[1/3]") { return Event(fraction: 0.05, message: "Preparing") }
        if line.contains("Downloading") { return Event(fraction: 0.1, message: line.trimmingCharacters(in: .whitespaces)) }
        if line.contains("Loading model") { return Event(fraction: 0.2, message: "Loading model") }
        if line.contains("Processing full image") { return Event(fraction: nil, message: "Upscaling image") }
        if line.contains("Tiles:"),
           let match = line.range(of: #"[0-9]+/[0-9]+"#, options: .regularExpression) {
            let parts = line[match].split(separator: "/").compactMap { Double($0) }
            if parts.count == 2, parts[1] > 0 {
                return Event(fraction: 0.2 + 0.7 * parts[0] / parts[1], message: "Upscaling tile \(Int(parts[0])) of \(Int(parts[1]))")
            }
        }
        if line.contains("Saving output") { return Event(fraction: 0.95, message: "Saving") }
        if line.contains("[3/3] Complete") { return Event(fraction: 1, message: "Complete") }
        return Event(fraction: nil, message: line.trimmingCharacters(in: .whitespaces))
    }
}
