import Foundation

enum OutputNaming {
    static func validatedOutputURL(input: URL, options: UpscaleOptions) throws -> URL {
        let ext = options.format.fileExtension(for: input)
        guard ["png", "jpg", "jpeg", "jxl", "webp"].contains(ext) else {
            throw NamingError.unsupportedInputExtension(ext)
        }
        return options.outputURL(for: input)
    }

    enum NamingError: LocalizedError {
        case unsupportedInputExtension(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedInputExtension(let ext):
                "The .\(ext) format cannot be used as an output. Choose PNG, JPG, JXL, or WebP."
            }
        }
    }
}
