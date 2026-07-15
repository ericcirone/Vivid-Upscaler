import Foundation

enum UpscaleMode: String, CaseIterable, Identifiable, Codable {
    case fast
    case normal
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: "Fast"
        case .normal: "Normal"
        case .advanced: "Advanced"
        }
    }

    var detail: String {
        switch self {
        case .fast: "Quick previews and everyday photos"
        case .normal: "Best balance of detail and speed"
        case .advanced: "Maximum restoration; much slower"
        }
    }
}

enum SizingKind: String, CaseIterable, Identifiable {
    case scale
    case resolution

    var id: String { rawValue }
    var title: String { self == .scale ? "Scale" : "Resolution" }
}

enum OutputFormat: String, CaseIterable, Identifiable {
    case same
    case png
    case jpg
    case jxl
    case webp

    var id: String { rawValue }
    var title: String { self == .same ? "Same as input" : rawValue.uppercased() }

    func fileExtension(for inputURL: URL) -> String {
        self == .same ? inputURL.pathExtension.lowercased() : rawValue
    }
}

struct UpscaleOptions {
    var mode: UpscaleMode
    var sizingKind: SizingKind
    var scale: Double
    var resolution: Int
    var maxResolution: Int
    var format: OutputFormat

    var sizingToken: String {
        switch sizingKind {
        case .scale:
            let value = scale.rounded() == scale ? String(Int(scale)) : String(format: "%g", scale)
            return "\(value)x"
        case .resolution:
            return "\(resolution)px"
        }
    }

    func outputURL(for inputURL: URL) -> URL {
        let ext = format.fileExtension(for: inputURL)
        let filename = "\(inputURL.deletingPathExtension().lastPathComponent)-vivid-upscale-\(sizingToken).\(ext)"
        return inputURL.deletingLastPathComponent().appendingPathComponent(filename)
    }
}
