import Foundation

struct ModelInfo: Identifiable, Hashable {
    let id: String
    let mode: UpscaleMode
    let title: String
    let detail: String
    let sizeNote: String

    static let choices: [ModelInfo] = [
        .init(id: "fast", mode: .fast, title: "Fast", detail: "RealESRGAN for quick, clean enlargement.", sizeNote: "Smallest download"),
        .init(id: "normal", mode: .normal, title: "Normal", detail: "Nomos Web Photo for a strong quality/speed balance.", sizeNote: "Recommended"),
        .init(id: "advanced-3b", mode: .advanced, title: "Advanced 3B", detail: "SeedVR2 restoration for difficult or damaged photos.", sizeNote: "Large download")
    ]
}
