import Foundation

enum UpscaleMode: String, CaseIterable, Identifiable, Codable {
    case fast
    case normal
    case normalHQ = "normal-hq"
    case creative
    case advanced
    case maximum

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: "Fast"
        case .normal: "Normal"
        case .normalHQ: "Normal HQ"
        case .creative: "Creative"
        case .advanced: "Advanced"
        case .maximum: "Maximum"
        }
    }

    var detail: String {
        switch self {
        case .fast: "Fastest general-purpose upscaling"
        case .normal: "Best balance for compressed or imperfect photos"
        case .normalHQ: "Best for clean, high-quality source photos"
        case .creative: "Aggressive generated detail; may alter identity-sensitive features"
        case .advanced: "Faster SeedVR2 restoration with reduced memory use"
        case .maximum: "Highest-quality SeedVR2 processing; slowest and most memory intensive"
        }
    }

    var minimumRAMGB: Int {
        switch self {
        case .fast: 8
        case .normal, .normalHQ, .creative, .advanced: 16
        case .maximum: 24
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
