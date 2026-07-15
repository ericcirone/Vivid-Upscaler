import Foundation

struct ModelInfo: Identifiable, Hashable {
    let id: String
    let mode: UpscaleMode
    let title: String
    let modelName: String
    let minimumRAMGB: Int
    let recommendedRAMGB: Int
    let largeImageRAMGB: Int
    let defaultTiling: String
    let intendedUse: String

    var detail: String { intendedUse }
    var sizeNote: String { "\(minimumRAMGB) GB minimum" }

    func isCompatible(withRAMGB ramGB: Int) -> Bool {
        ramGB >= minimumRAMGB
    }

    static func info(for id: String) -> ModelInfo? {
        choices.first { $0.id == id }
    }

    static let choices: [ModelInfo] = [
        .init(id: "fast", mode: .fast, title: "Fast", modelName: "realesr-general-x4v3", minimumRAMGB: 8, recommendedRAMGB: 16, largeImageRAMGB: 24, defaultTiling: "auto", intendedUse: "Fastest general-purpose upscaling. Uses forced tiling on 8 GB systems."),
        .init(id: "normal", mode: .normal, title: "Normal", modelName: "4xNomosWebPhoto_atd", minimumRAMGB: 16, recommendedRAMGB: 16, largeImageRAMGB: 24, defaultTiling: "auto", intendedUse: "Best general-purpose balance for compressed, resized, noisy, or slightly blurry photographs."),
        .init(id: "normal-hq", mode: .normalHQ, title: "Normal HQ", modelName: "4xNomos2_hq_atd", minimumRAMGB: 16, recommendedRAMGB: 16, largeImageRAMGB: 24, defaultTiling: "auto", intendedUse: "Best for clean camera originals and already high-quality source photographs."),
        .init(id: "creative", mode: .creative, title: "Creative", modelName: "AuraSR v2", minimumRAMGB: 16, recommendedRAMGB: 24, largeImageRAMGB: 32, defaultTiling: "auto", intendedUse: "More aggressive generated detail. May alter faces, textures, or identity-sensitive details."),
        .init(id: "advanced", mode: .advanced, title: "Advanced", modelName: "SeedVR2 3B FP8", minimumRAMGB: 16, recommendedRAMGB: 24, largeImageRAMGB: 32, defaultTiling: "auto", intendedUse: "Faster SeedVR2 restoration with reduced memory use and quality close to FP16."),
        .init(id: "maximum", mode: .maximum, title: "Maximum", modelName: "SeedVR2 3B FP16", minimumRAMGB: 24, recommendedRAMGB: 32, largeImageRAMGB: 48, defaultTiling: "auto", intendedUse: "Highest-quality SeedVR2 processing. Slowest mode and most memory intensive.")
    ]
}
