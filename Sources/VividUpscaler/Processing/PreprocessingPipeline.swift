import Foundation

enum PreprocessingStep: Equatable {
    case photoRestore(PhotoRestoreSettings)
    case deblur(DeblurMode)
    case faceRestore(CodeFormerOptions)
}

struct PreprocessingPipeline: Equatable {
    let steps: [PreprocessingStep]

    /// Mirrors the CLI order: general restoration first so deblurring and
    /// face detection see a photo without noise and compression artifacts.
    init(
        photoRestoreOptions: PhotoRestoreOptions = .init(),
        deblurMode: DeblurMode,
        codeFormerOptions: CodeFormerOptions
    ) {
        var steps: [PreprocessingStep] = []
        if photoRestoreOptions.isEnabled {
            steps.append(.photoRestore(photoRestoreOptions.resolvedSettings))
        }
        if deblurMode != .none {
            steps.append(.deblur(deblurMode))
        }
        if codeFormerOptions.isEnabled {
            steps.append(.faceRestore(codeFormerOptions))
        }
        self.steps = steps
    }
}
