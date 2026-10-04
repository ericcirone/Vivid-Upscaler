import Foundation

enum OutputNaming {
    static func validatedOutputURL(input: URL, options: UpscaleOptions, directory: URL? = nil) throws -> URL {
        let ext = options.format.fileExtension(for: input)
        guard OutputFormat.writableExtensions.contains(ext) else {
            throw NamingError.unsupportedOutputExtension(ext)
        }
        return options.outputURL(for: input, in: directory)
    }

    /// Assigns each input an output URL, adding a numeric suffix when two
    /// inputs in the same batch would otherwise write the same file.
    static func uniqueOutputURLs(inputs: [URL], options: UpscaleOptions, directory: URL?) throws -> [URL] {
        var claimed: Set<String> = []
        return try inputs.map { input in
            let base = try validatedOutputURL(input: input, options: options, directory: directory)
            var candidate = base
            var index = 2
            while claimed.contains(candidate.standardizedFileURL.path.lowercased()) {
                let stem = base.deletingPathExtension().lastPathComponent
                candidate = base.deletingLastPathComponent()
                    .appendingPathComponent("\(stem)-\(index)")
                    .appendingPathExtension(base.pathExtension)
                index += 1
            }
            claimed.insert(candidate.standardizedFileURL.path.lowercased())
            return candidate
        }
    }

    enum NamingError: LocalizedError {
        case unsupportedOutputExtension(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedOutputExtension(let ext):
                "The .\(ext) format cannot be used as an output. Choose PNG, JPG, JPEG XL, WebP, AVIF, or TIFF."
            }
        }
    }
}
