import CoreGraphics
import Foundation

enum UpscaleMode: String, CaseIterable, Identifiable, Codable {
    case fast
    case normal
    case normalHQ = "normal-hq"
    case art
    case advanced
    case maximum
    case maximumExperimental = "maximum-experimental"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: "Fast"
        case .normal: "Normal"
        case .normalHQ: "Normal HQ"
        case .art: "Art & Anime"
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
        case .art: "Illustrations, anime, cartoons, and line art with clean edges"
        case .advanced: "8-bit SeedVR2 at 80% internal scale for faster high-quality restoration"
        case .maximum: "Highest-quality SeedVR2 processing; slowest and most memory intensive"
        case .maximumExperimental: "Experimental HYPIR generative restoration; may reconstruct plausible detail"
        }
    }

    var minimumRAMGB: Int {
        switch self {
        case .fast, .art: 8
        case .normal, .normalHQ, .advanced: 16
        case .maximum, .maximumExperimental: 24
        }
    }

    var isExperimental: Bool { self == .maximumExperimental }

    /// Fast mode blends Real-ESRGAN general-x4v3 with its denoising sibling.
    var supportsNoiseReduction: Bool { self == .fast }
}

enum SizingKind: String, CaseIterable, Identifiable {
    case scale
    case resolution
    /// Keep the source dimensions and skip the upscaling model entirely, so
    /// only the enabled enhancements run.
    case original

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scale: "Scale"
        case .resolution: "Resolution"
        case .original: "Original"
        }
    }
}

enum OutputFormat: String, CaseIterable, Identifiable {
    case same
    case png
    case jpg
    case jxl
    case webp
    case avif
    case tiff

    static let writableExtensions: Set<String> = ["png", "jpg", "jpeg", "jxl", "webp", "avif", "tif", "tiff"]
    static let qualityExtensions: Set<String> = ["jpg", "jpeg", "jxl", "webp", "avif"]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .same: "Same as input"
        case .jxl: "JPEG XL"
        default: rawValue.uppercased()
        }
    }

    /// The extension written for `inputURL`. Formats Vivid reads but cannot
    /// write fall back to the closest sensible output.
    func fileExtension(for inputURL: URL) -> String {
        guard self == .same else { return rawValue }
        let inputExtension = inputURL.pathExtension.lowercased()
        if Self.writableExtensions.contains(inputExtension) { return inputExtension }
        return ["heic", "heif"].contains(inputExtension) ? "jpg" : "png"
    }

    func supportsQuality(for inputURL: URL?) -> Bool {
        if self == .same {
            guard let inputURL else { return false }
            return Self.qualityExtensions.contains(fileExtension(for: inputURL))
        }
        return Self.qualityExtensions.contains(rawValue)
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
    static let defaultNoiseReduction = 0.5

    var mode: UpscaleMode
    var photoRestoreOptions: PhotoRestoreOptions = .init()
    var deblurMode: DeblurMode = .none
    var codeFormerOptions: CodeFormerOptions = .init()
    var generativeOptions: GenerativeOptions = .init()
    var seedVR2Options: SeedVR2Options = .init()
    var hypirOptions: HYPIROptions = .init()
    var noiseReduction: Double = Self.defaultNoiseReduction
    var sizingKind: SizingKind
    var scale: Double
    var resolution: Int
    var maxResolution: Int
    var format: OutputFormat
    var quality: Double

    var preprocessingPipeline: PreprocessingPipeline {
        PreprocessingPipeline(
            photoRestoreOptions: photoRestoreOptions,
            deblurMode: deblurMode,
            codeFormerOptions: codeFormerOptions
        )
    }

    /// Whether the selected upscaling model runs at all.
    var upscales: Bool { sizingKind != .original }

    var hasEnhancements: Bool { !preprocessingPipeline.steps.isEmpty }

    var sizingToken: String {
        switch sizingKind {
        case .scale:
            let value = scale.rounded() == scale ? String(Int(scale)) : String(format: "%g", scale)
            return "\(value)x"
        case .resolution:
            return "\(resolution)px"
        case .original:
            return "original"
        }
    }

    /// The CLI's `--denoise-strength` keeps more of the source noise as it
    /// rises, so the app's noise-reduction amount is its complement.
    var cliDenoiseStrength: Double {
        1 - min(max(noiseReduction, 0), 1)
    }

    func outputURL(for inputURL: URL, in directory: URL? = nil) -> URL {
        let ext = format.fileExtension(for: inputURL)
        let photoRestoreToken = photoRestoreOptions.isEnabled ? "-photo-restore" : ""
        let deblurToken = deblurMode == .none ? "" : "-\(deblurMode.rawValue)"
        let faceRestoreToken = codeFormerOptions.isEnabled ? "-face-restore" : ""
        let enhancementTokens = "\(photoRestoreToken)\(deblurToken)\(faceRestoreToken)"
        let stem = inputURL.deletingPathExtension().lastPathComponent
        let filename = upscales
            ? "\(stem)-vivid-upscale-\(mode.rawValue)\(enhancementTokens)-\(sizingToken).\(ext)"
            : "\(stem)-vivid\(enhancementTokens)-\(sizingToken).\(ext)"
        return (directory ?? inputURL.deletingLastPathComponent()).appendingPathComponent(filename)
    }

    /// Mirrors the CLI's target-size calculation so the app can preview the
    /// exact output dimensions before processing.
    func outputPixelSize(for source: CGSize) -> CGSize? {
        guard source.width >= 1, source.height >= 1 else { return nil }
        let shortSide = min(source.width, source.height)
        let longSide = max(source.width, source.height)
        let shortEdge: Double
        let maxLongEdge: Double
        switch sizingKind {
        case .scale:
            guard scale > 0 else { return nil }
            shortEdge = max(1, (shortSide * scale).rounded())
            maxLongEdge = max(1, (longSide * scale).rounded())
        case .resolution:
            guard resolution > 0, maxResolution > 0 else { return nil }
            shortEdge = Double(resolution)
            maxLongEdge = Double(maxResolution)
        case .original:
            return CGSize(width: source.width.rounded(), height: source.height.rounded())
        }
        var factor = shortEdge / shortSide
        if longSide * factor > maxLongEdge {
            factor = maxLongEdge / longSide
        }
        return CGSize(
            width: max(1, (source.width * factor).rounded()),
            height: max(1, (source.height * factor).rounded())
        )
    }
}
