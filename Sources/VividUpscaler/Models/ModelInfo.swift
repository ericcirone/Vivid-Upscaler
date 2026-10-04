import Foundation

struct ModelInfo: Identifiable, Hashable {
    let id: String
    let mode: UpscaleMode?
    let deblurMode: DeblurMode?
    var isFaceRestore = false
    let title: String
    let modelName: String
    let backend: String
    let minimumRAMGB: Int
    let recommendedRAMGB: Int
    let largeImageRAMGB: Int
    let defaultTiling: String
    let intendedUse: String
    /// Approximate download size, used for the model manager's estimates.
    let downloadMB: Int
    /// Models that share weights with this one and are removed together.
    var sharesWeightsWith: [String] = []

    var detail: String { intendedUse }

    var formattedDownloadSize: String {
        Self.formatDownloadSize(megabytes: downloadMB)
    }

    static func formatDownloadSize(megabytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(megabytes) * 1_000_000, countStyle: .file)
    }

    func isCompatible(withRAMGB ramGB: Int) -> Bool {
        ramGB >= minimumRAMGB
    }

    static func info(for id: String) -> ModelInfo? {
        choices.first { $0.id == id }
    }

    static var upscaleChoices: [ModelInfo] {
        choices.filter { $0.mode != nil }
    }

    static var enhancementChoices: [ModelInfo] {
        choices.filter { $0.mode == nil }
    }

    static var deblurChoices: [ModelInfo] {
        choices.filter { $0.deblurMode != nil }
    }

    static var faceRestoreChoice: ModelInfo? {
        choices.first(where: \.isFaceRestore)
    }

    /// Estimated download for `ids`, counting shared weights only once.
    static func downloadMB(for ids: some Sequence<String>) -> Int {
        var counted: Set<String> = []
        var total = 0
        for id in ids {
            guard let model = info(for: id), !counted.contains(id) else { continue }
            counted.insert(id)
            counted.formUnion(model.sharesWeightsWith)
            total += model.downloadMB
        }
        return total
    }

    static let choices: [ModelInfo] = [
        .init(id: "fast", mode: .fast, deblurMode: nil, title: "Fast", modelName: "mlx-community/Real-ESRGAN-general-x4v3", backend: "MLX", minimumRAMGB: 8, recommendedRAMGB: 16, largeImageRAMGB: 24, defaultTiling: "auto", intendedUse: "Quickest option: a compact native FP16 MLX upscaler for Apple Silicon with adjustable noise reduction.", downloadMB: 5),
        .init(id: "normal", mode: .normal, deblurMode: nil, title: "Normal", modelName: "mlx-community/Real-ESRGAN-x4plus", backend: "MLX", minimumRAMGB: 16, recommendedRAMGB: 16, largeImageRAMGB: 24, defaultTiling: "auto", intendedUse: "The main quality and speed balance with a more powerful conventional single-pass upscaler.", downloadMB: 34),
        .init(id: "normal-hq", mode: .normalHQ, deblurMode: nil, title: "Normal HQ", modelName: "4xNomosWebPhoto_esrgan", backend: "PyTorch MPS via Spandrel", minimumRAMGB: 16, recommendedRAMGB: 16, largeImageRAMGB: 24, defaultTiling: "auto", intendedUse: "Fast photographic restoration trained for compression, lens blur, noise, and Web/JPEG sources.", downloadMB: 34),
        .init(id: "art", mode: .art, deblurMode: nil, title: "Art & Anime", modelName: "mlx-community/Real-ESRGAN-x4plus-anime-6B", backend: "MLX", minimumRAMGB: 8, recommendedRAMGB: 16, largeImageRAMGB: 24, defaultTiling: "auto", intendedUse: "Illustrations, anime, cartoons, and line art: keeps flat colors clean and edges crisp instead of inventing photographic texture.", downloadMB: 9),
        .init(id: "advanced", mode: .advanced, deblurMode: nil, title: "Advanced", modelName: "SeedVR2 3B 8-bit, 80% internal scale", backend: "Native MLX", minimumRAMGB: 16, recommendedRAMGB: 24, largeImageRAMGB: 32, defaultTiling: "auto", intendedUse: "High-quality SeedVR2 restoration using 8-bit precision and a reduced internal resolution for a meaningful speed improvement over Maximum.", downloadMB: 6_800, sharesWeightsWith: ["maximum"]),
        .init(id: "maximum", mode: .maximum, deblurMode: nil, title: "Maximum", modelName: "SeedVR2 3B source precision", backend: "Native MLX", minimumRAMGB: 24, recommendedRAMGB: 32, largeImageRAMGB: 48, defaultTiling: "auto", intendedUse: "Highest-quality, slowest SeedVR2 option using the 3B model at source precision.", downloadMB: 6_800, sharesWeightsWith: ["advanced"]),
        .init(id: "maximum-experimental", mode: .maximumExperimental, deblurMode: nil, title: "Maximum Experimental", modelName: "HYPIR-SD2", backend: "PyTorch MPS, experimental", minimumRAMGB: 24, recommendedRAMGB: 32, largeImageRAMGB: 48, defaultTiling: "auto", intendedUse: "Maximum-tier experimental generative restoration using a single-pass diffusion-derived model for strong detail reconstruction and adjustable texture richness.", downloadMB: 3_400),
        .init(id: "deblur-motion", mode: nil, deblurMode: .motion, title: "Motion Blur", modelName: "Restormer Motion Deblurring", backend: "PyTorch MPS", minimumRAMGB: 16, recommendedRAMGB: 24, largeImageRAMGB: 32, defaultTiling: "auto", intendedUse: "Removes camera shake, subject movement, and directional motion blur while preserving the original image dimensions.", downloadMB: 105),
        .init(id: "deblur-defocus", mode: nil, deblurMode: .defocus, title: "Out of Focus", modelName: "Restormer Single-Image Defocus Deblurring", backend: "PyTorch MPS", minimumRAMGB: 16, recommendedRAMGB: 24, largeImageRAMGB: 32, defaultTiling: "auto", intendedUse: "Reduces out-of-focus and lens-related blur while preserving the original image dimensions.", downloadMB: 105),
        .init(id: "face-restore", mode: nil, deblurMode: nil, isFaceRestore: true, title: "Face Restore", modelName: "CodeFormer v0.1.0", backend: "PyTorch MPS via Vivid adapter", minimumRAMGB: 8, recommendedRAMGB: 16, largeImageRAMGB: 24, defaultTiling: "face crops", intendedUse: "Restores detected faces with an adjustable balance between stronger reconstruction and closer identity preservation.", downloadMB: 570)
    ]
}
