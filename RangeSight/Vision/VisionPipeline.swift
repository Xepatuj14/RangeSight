public enum VisionPipelineStage: String, Codable, CaseIterable, Equatable, Sendable {
    case targetAcquisition
    case perspectiveNormalization
    case frameRegistration
    case changeMapGeneration
    case candidateExtraction
    case temporalConfirmation
    case shotEventEmission
}

public struct VisionPipelineBoundary: Sendable {
    public let stages: [VisionPipelineStage]

    public init(stages: [VisionPipelineStage] = VisionPipelineStage.allCases) {
        self.stages = stages
    }
}
