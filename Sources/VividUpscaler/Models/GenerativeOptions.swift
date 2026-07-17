import Foundation

struct GenerativeOptions: Equatable {
    static let defaultVariationSeed = 42

    var variationSeed: Int = Self.defaultVariationSeed
}

extension UpscaleMode {
    var supportsVariationSeed: Bool {
        switch self {
        case .advanced, .maximum, .maximumExperimental: true
        case .fast, .normal, .normalHQ: false
        }
    }
}
