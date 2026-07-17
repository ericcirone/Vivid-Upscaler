import Foundation

enum HYPIRPreset: String, CaseIterable, Identifiable, Codable {
    case natural
    case balanced
    case enhanced
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .natural: "Natural"
        case .balanced: "Balanced"
        case .enhanced: "Enhanced"
        case .custom: "Custom"
        }
    }

    var detail: String {
        switch self {
        case .natural: "Restrained generated detail while preserving more source texture."
        case .balanced: "Balances generated detail, source fidelity, memory use, and speed."
        case .enhanced: "Full HYPIR-generated detail with stronger overlap at a substantial speed cost."
        case .custom: "Uses your restoration strength, prompt, patch size, and patch stride."
        }
    }

    var settings: HYPIRSettings? {
        switch self {
        case .natural:
            .init(
                restorationStrength: 0.45,
                patchSize: 1024,
                patchStride: 768,
                prompt: "a natural photograph, realistic skin texture, accurate facial features, subtle detail, soft photographic sharpness"
            )
        case .balanced:
            .init(
                restorationStrength: 0.70,
                patchSize: 768,
                patchStride: 512,
                prompt: HYPIRSettings.balancedPrompt
            )
        case .enhanced:
            .init(
                restorationStrength: 1.00,
                patchSize: 512,
                patchStride: 256,
                prompt: "a highly detailed professional photograph, sharp facial features, clear fine textures, crisp hair, detailed clothing"
            )
        case .custom:
            nil
        }
    }
}

struct HYPIRSettings: Equatable {
    static let balancedPrompt = "a detailed realistic photograph, natural textures, clear facial features, balanced photographic sharpness"
    static let supportedPatchSizes = Array(stride(from: 512, through: 1024, by: 128))

    var restorationStrength: Double
    var patchSize: Int
    var patchStride: Int
    var prompt: String

    static func supportedPatchStrides(for patchSize: Int) -> [Int] {
        Array(stride(from: 256, through: normalizedPatchSize(patchSize), by: 128))
    }

    static func normalizedPatchSize(_ value: Int) -> Int {
        supportedPatchSizes.min { abs($0 - value) < abs($1 - value) } ?? 768
    }

    static func normalizedPatchStride(_ value: Int, patchSize: Int) -> Int {
        let supported = supportedPatchStrides(for: patchSize)
        return supported.min { abs($0 - value) < abs($1 - value) } ?? min(512, patchSize)
    }
}

struct HYPIROptions: Equatable {
    var preset: HYPIRPreset = .balanced
    var customRestorationStrength: Double = 0.70
    var customPatchSize: Int = 768
    var customPatchStride: Int = 512
    var customPrompt: String = HYPIRSettings.balancedPrompt

    var resolvedSettings: HYPIRSettings {
        if let settings = preset.settings {
            return settings
        }

        let patchSize = HYPIRSettings.normalizedPatchSize(customPatchSize)
        return .init(
            restorationStrength: min(max(customRestorationStrength, 0), 1),
            patchSize: patchSize,
            patchStride: HYPIRSettings.normalizedPatchStride(customPatchStride, patchSize: patchSize),
            prompt: customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? HYPIRSettings.balancedPrompt
                : customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

extension UpscaleMode {
    var supportsHYPIRSettings: Bool {
        self == .maximumExperimental
    }
}
