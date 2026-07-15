import Foundation

enum DeblurMode: String, CaseIterable, Identifiable, Codable {
    case none
    case motion = "deblur-motion"
    case defocus = "deblur-defocus"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .motion: "Motion Blur"
        case .defocus: "Out of Focus"
        }
    }

    var detail: String {
        switch self {
        case .none: "Upscale the source without a deblur preprocessing pass."
        case .motion: "Remove camera shake, subject movement, and directional smearing."
        case .defocus: "Reduce out-of-focus and lens-related blur."
        }
    }

    var modelID: String? {
        self == .none ? nil : rawValue
    }

    var minimumRAMGB: Int {
        self == .none ? 0 : 16
    }
}
