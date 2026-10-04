import Foundation

enum PhotoRestorePreset: String, CaseIterable, Identifiable, Codable {
    case gentle
    case balanced
    case strong
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gentle: "Gentle"
        case .balanced: "Balanced"
        case .strong: "Strong"
        case .custom: "Custom"
        }
    }

    var detail: String {
        switch self {
        case .gentle: "Light cleanup that keeps some of the original grain. Best for photos that are already fairly good."
        case .balanced: "Removes most noise and compression artifacts while keeping a trace of natural texture. Recommended."
        case .strong: "Full cleanup with crisper reconstructed texture for heavily degraded, noisy, or over-compressed photos."
        case .custom: "Choose the restoration strength and detail style directly."
        }
    }

    var settings: PhotoRestoreSettings? {
        switch self {
        case .gentle: .init(strength: 0.60, detail: .natural)
        case .balanced: .init(strength: 0.85, detail: .natural)
        case .strong: .init(strength: 1.00, detail: .sharp)
        case .custom: nil
        }
    }
}

/// Selects which SCUNet weights restore the photo.
enum PhotoRestoreDetail: String, CaseIterable, Identifiable, Codable {
    /// Fidelity-trained weights: the closest match to the original scene.
    case natural
    /// GAN-trained weights: crisper texture that may be partly reconstructed.
    case sharp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .natural: "Natural"
        case .sharp: "Sharp"
        }
    }
}

struct PhotoRestoreSettings: Equatable {
    /// Share of the source's fine detail (noise, grain, artifacts) that is
    /// replaced by the restored result. Coarse tones and colors always come
    /// from the original photo.
    var strength: Double
    var detail: PhotoRestoreDetail
}

struct PhotoRestoreOptions: Equatable {
    var isEnabled = false
    var preset: PhotoRestorePreset = .balanced
    var customStrength = 0.85
    var customDetail: PhotoRestoreDetail = .natural

    var resolvedSettings: PhotoRestoreSettings {
        preset.settings ?? .init(strength: min(max(customStrength, 0), 1), detail: customDetail)
    }
}
