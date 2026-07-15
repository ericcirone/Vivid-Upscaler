import Foundation

struct ModelInfo: Identifiable, Hashable {
    let id: String
    let mode: UpscaleMode?
    let deblurMode: DeblurMode?
    let title: String
    let modelName: String
    let backend: String
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

    static var upscaleChoices: [ModelInfo] {
        choices.filter { $0.mode != nil }
    }

    static var deblurChoices: [ModelInfo] {
        choices.filter { $0.deblurMode != nil }
    }

    static let choices: [ModelInfo] = [
        .init(id: "fast", mode: .fast, deblurMode: nil, title: "Fast", modelName: "mlx-community/Real-ESRGAN-general-x4v3", backend: "MLX", minimumRAMGB: 8, recommendedRAMGB: 16, largeImageRAMGB: 24, defaultTiling: "auto", intendedUse: "Quickest option: a compact native FP16 MLX upscaler for Apple Silicon."),
        .init(id: "normal", mode: .normal, deblurMode: nil, title: "Normal", modelName: "mlx-community/Real-ESRGAN-x4plus", backend: "MLX", minimumRAMGB: 16, recommendedRAMGB: 16, largeImageRAMGB: 24, defaultTiling: "auto", intendedUse: "The main quality and speed balance with a more powerful conventional single-pass upscaler."),
        .init(id: "normal-hq", mode: .normalHQ, deblurMode: nil, title: "Normal HQ", modelName: "4xNomosWebPhoto_esrgan", backend: "PyTorch MPS via Spandrel", minimumRAMGB: 16, recommendedRAMGB: 16, largeImageRAMGB: 24, defaultTiling: "auto", intendedUse: "Fast photographic restoration trained for compression, lens blur, noise, and Web/JPEG sources."),
        .init(id: "advanced", mode: .advanced, deblurMode: nil, title: "Advanced", modelName: "SeedVR2 3B 8-bit", backend: "Native MLX", minimumRAMGB: 16, recommendedRAMGB: 24, largeImageRAMGB: 32, defaultTiling: "auto", intendedUse: "Difficult restoration jobs where a longer wait is acceptable, using the 3B model at 8-bit precision."),
        .init(id: "maximum", mode: .maximum, deblurMode: nil, title: "Maximum", modelName: "SeedVR2 3B source precision", backend: "Native MLX", minimumRAMGB: 24, recommendedRAMGB: 32, largeImageRAMGB: 48, defaultTiling: "auto", intendedUse: "Highest-quality, slowest SeedVR2 option using the 3B model at source precision."),
        .init(id: "deblur-motion", mode: nil, deblurMode: .motion, title: "Motion Blur", modelName: "Restormer Motion Deblurring", backend: "PyTorch MPS", minimumRAMGB: 16, recommendedRAMGB: 24, largeImageRAMGB: 32, defaultTiling: "auto", intendedUse: "Removes camera shake, subject movement, and directional motion blur while preserving the original image dimensions."),
        .init(id: "deblur-defocus", mode: nil, deblurMode: .defocus, title: "Out of Focus", modelName: "Restormer Single-Image Defocus Deblurring", backend: "PyTorch MPS", minimumRAMGB: 16, recommendedRAMGB: 24, largeImageRAMGB: 32, defaultTiling: "auto", intendedUse: "Reduces out-of-focus and lens-related blur while preserving the original image dimensions.")
    ]
}
