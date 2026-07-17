import Foundation

enum UpscaleMode: String, CaseIterable, Identifiable, Codable {
    case fast
    case normal
    case normalHQ = "normal-hq"
    case advanced
    case maximum
    case maximumExperimental = "maximum-experimental"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: "Fast"
        case .normal: "Normal"
        case .normalHQ: "Normal HQ"
        case .advanced: "Advanced"
        case .maximum: "Maximum"
        case .maximumExperimental: "Maximum Experimental"
        }
    }

    var detail: String {
        switch self {
        case .fast: "Quickest general-purpose MLX upscaling"
        case .normal: "Main quality and speed balance"
        case .normalHQ: "Photographic restoration for compression, blur, and noise"
        case .advanced: "Native MLX SeedVR2 restoration with 8-bit weights"
        case .maximum: "Highest-quality SeedVR2 processing; slowest and most memory intensive"
        case .maximumExperimental: "Experimental HYPIR generative restoration; may reconstruct plausible detail"
        }
    }

    var minimumRAMGB: Int {
        switch self {
        case .fast: 8
        case .normal, .normalHQ, .advanced: 16
        case .maximum, .maximumExperimental: 24
        }
    }

    var isExperimental: Bool { self == .maximumExperimental }
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

    func supportsQuality(for inputURL: URL?) -> Bool {
        let fileExtension: String
        if self == .same {
            guard let inputURL else { return false }
            fileExtension = inputURL.pathExtension.lowercased()
        } else {
            fileExtension = rawValue
        }
        return ["jpg", "jpeg", "jxl", "webp"].contains(fileExtension)
    }
}

enum OutputQualityPreset: Int, CaseIterable, Identifiable {
    case low = 60
    case medium = 75
    case high = 85
    case extraHigh = 90

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .low: "Low"
        case .medium: "Med"
        case .high: "High"
        case .extraHigh: "X-High"
        }
    }

    var index: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    static func nearest(to quality: Double) -> Self {
        allCases.min {
            abs(Double($0.rawValue) - quality) < abs(Double($1.rawValue) - quality)
        } ?? .high
    }
}

struct UpscaleOptions {
    var mode: UpscaleMode
    var deblurMode: DeblurMode = .none
    var sizingKind: SizingKind
    var scale: Double
    var resolution: Int
    var maxResolution: Int
    var format: OutputFormat
    var quality: Double

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
        let deblurToken = deblurMode == .none ? "" : "-\(deblurMode.rawValue)"
        let filename = "\(inputURL.deletingPathExtension().lastPathComponent)-vivid-upscale-\(mode.rawValue)\(deblurToken)-\(sizingToken).\(ext)"
        return inputURL.deletingLastPathComponent().appendingPathComponent(filename)
    }
}
