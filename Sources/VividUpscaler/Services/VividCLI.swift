import Foundation

actor VividCLI {
    struct Event: Sendable {
        let fraction: Double?
        let message: String
    }

    enum CLIError: LocalizedError {
        case notInstalled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                "Vivid CLI is not installed. Run ./install.sh, then reopen the app."
            case .failed(let message):
                message.isEmpty ? "Vivid CLI failed." : message
            }
        }
    }

    private var process: Process?

    func executableURL() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        var candidates: [String] = []
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
        for (index, id) in ids.enumerated() {
            let base = Double(index) / Double(max(ids.count, 1))
            let span = 1.0 / Double(max(ids.count, 1))
            try await run(arguments: ["models", "install", id]) { line in
                let local = Self.percentage(in: line)
                onEvent(Event(fraction: local.map { base + ($0 * span) }, message: line))
            }
        }
    }

    func upscale(
        input: URL,
        output: URL,
        options: UpscaleOptions,
        onEvent: @escaping @Sendable (Event) -> Void
    ) async throws {
        var arguments = [input.path, output.path, "--mode", options.mode.rawValue]
        switch options.sizingKind {
        case .scale:
            arguments += ["--scale", String(options.scale)]
        case .resolution:
            arguments += ["--resolution", String(options.resolution), "--max-resolution", String(options.maxResolution)]
        }

        try await run(arguments: arguments) { line in
            onEvent(Self.event(for: line))
        }
    }

    func cancel() {
        process?.terminate()
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

        let task = Process()
        let pipe = Pipe()
        task.executableURL = executable
        task.arguments = arguments
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
