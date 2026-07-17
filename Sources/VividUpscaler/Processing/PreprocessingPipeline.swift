import Foundation

enum PreprocessingStep: Equatable {
    case deblur(DeblurMode)
    case faceRestore(CodeFormerOptions)
}

struct PreprocessingPipeline: Equatable {
    let steps: [PreprocessingStep]

    init(deblurMode: DeblurMode, codeFormerOptions: CodeFormerOptions) {
        var steps: [PreprocessingStep] = []
        if deblurMode != .none {
            steps.append(.deblur(deblurMode))
        }
        if codeFormerOptions.isEnabled {
            steps.append(.faceRestore(codeFormerOptions))
        }
        self.steps = steps
    }
}
