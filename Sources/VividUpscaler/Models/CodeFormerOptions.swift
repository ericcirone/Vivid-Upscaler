import Foundation

enum CodeFormerPreset: String, CaseIterable, Identifiable, Codable {
    case enhance
    case balanced
    case faithful
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .enhance: "Enhance"
        case .balanced: "Balanced"
        case .faithful: "Faithful"
        case .custom: "Custom"
        }
    }

    var detail: String {
        switch self {
        case .enhance: "Stronger reconstruction for heavily degraded, blurry, compressed, or very small faces."
        case .balanced: "Balances facial cleanup with identity preservation. Recommended for most photos."
        case .faithful: "Conservative restoration that prioritizes resemblance to the source face."
        case .custom: "Choose the fidelity trade-off directly."
        }
    }

    var fidelityWeight: Double? {
        switch self {
        case .enhance: 0.4
        case .balanced: 0.7
        case .faithful: 0.9
        case .custom: nil
        }
    }
}

struct CodeFormerOptions: Equatable {
    var isEnabled = false
    var preset: CodeFormerPreset = .balanced
    var customFidelityWeight = 0.7

    var resolvedFidelityWeight: Double {
        min(max(preset.fidelityWeight ?? customFidelityWeight, 0), 1)
    }
}
