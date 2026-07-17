import Foundation

enum SeedVR2ColorCorrection: String, CaseIterable, Identifiable, Codable {
    case lab
    case wavelet
    case waveletAdaptive = "wavelet_adaptive"
    case hsv
    case adain
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lab: "LAB"
        case .wavelet: "Wavelet"
        case .waveletAdaptive: "Wavelet Adaptive"
        case .hsv: "HSV"
        case .adain: "AdaIN"
        case .none: "None"
        }
    }
}

enum SeedVR2Preset: String, CaseIterable, Identifiable, Codable {
    case faithful
    case highResolutionCleanup = "high-resolution-cleanup"
    case softerDetail = "softer-detail"
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .faithful: "Faithful"
        case .highResolutionCleanup: "High-Resolution Cleanup"
        case .softerDetail: "Softer Detail"
        case .custom: "Custom"
        }
    }

    var detail: String {
        switch self {
        case .faithful: "Preserves the source and maintains strong color fidelity."
        case .highResolutionCleanup: "Reduces ringing and repeated artifacts at large output sizes."
        case .softerDetail: "Softens harsh reconstructed texture for a more photographic result."
        case .custom: "Uses your noise and color-correction settings."
        }
    }

    var settings: SeedVR2Settings? {
        switch self {
        case .faithful: .init(inputNoiseScale: 0, latentNoiseScale: 0, colorCorrection: .lab)
        case .highResolutionCleanup: .init(inputNoiseScale: 0.15, latentNoiseScale: 0, colorCorrection: .lab)
        case .softerDetail: .init(inputNoiseScale: 0, latentNoiseScale: 0.08, colorCorrection: .wavelet)
        case .custom: nil
        }
    }
}

struct SeedVR2Settings: Equatable {
    var inputNoiseScale: Double
    var latentNoiseScale: Double
    var colorCorrection: SeedVR2ColorCorrection
}

struct SeedVR2Options: Equatable {
    var preset: SeedVR2Preset = .faithful
    var customInputNoiseScale: Double = 0
    var customLatentNoiseScale: Double = 0
    var customColorCorrection: SeedVR2ColorCorrection = .lab

    var resolvedSettings: SeedVR2Settings {
        preset.settings ?? .init(
            inputNoiseScale: min(max(customInputNoiseScale, 0), 1),
            latentNoiseScale: min(max(customLatentNoiseScale, 0), 1),
            colorCorrection: customColorCorrection
        )
    }
}

extension UpscaleMode {
    var supportsSeedVR2Settings: Bool {
        self == .advanced || self == .maximum
    }
}
