import Foundation

public struct FrameDimensions: Codable, Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) throws {
        guard width > 0, height > 0 else {
            throw FrameSourceValidationError.invalidDimensions
        }

        self.width = width
        self.height = height
    }
}

public enum FrameOrientation: String, Codable, CaseIterable, Equatable, Sendable {
    case portrait
    case portraitUpsideDown
    case landscapeLeft
    case landscapeRight
}

public enum VisionFrameContent: Codable, Equatable, Sendable {
    case metadataOnly
    case fixtureData(String)
}

public struct VisionFrame: Codable, Equatable, Sendable {
    public let sequenceIndex: Int
    public let timestamp: TimeInterval
    public let dimensions: FrameDimensions
    public let orientation: FrameOrientation
    public let content: VisionFrameContent

    public init(
        sequenceIndex: Int,
        timestamp: TimeInterval,
        dimensions: FrameDimensions,
        orientation: FrameOrientation,
        content: VisionFrameContent = .metadataOnly
    ) throws {
        guard sequenceIndex >= 0 else {
            throw FrameSourceValidationError.invalidSequenceIndex
        }

        guard timestamp >= 0, timestamp.isFinite else {
            throw FrameSourceValidationError.invalidTimestamp
        }

        self.sequenceIndex = sequenceIndex
        self.timestamp = timestamp
        self.dimensions = dimensions
        self.orientation = orientation
        self.content = content
    }
}

public protocol VisionFrameSource: Sendable {
    mutating func nextFrame() async throws -> VisionFrame?
}

public struct VisionFrameDiagnostic: Codable, Equatable, Sendable {
    public let key: String
    public let value: Double

    public init(key: String, value: Double) throws {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FrameSourceValidationError.invalidDiagnosticKey
        }

        guard value.isFinite else {
            throw FrameSourceValidationError.invalidDiagnosticValue
        }

        self.key = key
        self.value = value
    }
}

public struct VisionPipelineEvent: Codable, Equatable, Sendable {
    public let frameSequenceIndex: Int
    public let frameTimestamp: TimeInterval
    public let stage: VisionPipelineStage
    public let diagnostics: [VisionFrameDiagnostic]

    public init(
        frameSequenceIndex: Int,
        frameTimestamp: TimeInterval,
        stage: VisionPipelineStage,
        diagnostics: [VisionFrameDiagnostic] = []
    ) {
        self.frameSequenceIndex = frameSequenceIndex
        self.frameTimestamp = frameTimestamp
        self.stage = stage
        self.diagnostics = diagnostics
    }
}

public protocol VisionFrameProcessor: Sendable {
    mutating func process(_ frame: VisionFrame) async throws -> [VisionPipelineEvent]
}

public enum FrameSourceValidationError: Error, Equatable {
    case invalidDimensions
    case invalidSequenceIndex
    case invalidTimestamp
    case invalidDiagnosticKey
    case invalidDiagnosticValue
}
