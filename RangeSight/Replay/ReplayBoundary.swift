import Foundation

public enum ReplayPlaybackMode: Codable, Equatable, Sendable {
    case frameByFrame
    case realtime
    case accelerated(Double)

    public var speedMultiplier: Double? {
        switch self {
        case .frameByFrame:
            return nil
        case .realtime:
            return 1
        case .accelerated(let speed):
            return speed
        }
    }
}

public struct ReplayRunConfiguration: Codable, Equatable, Sendable {
    public let algorithmVersion: String
    public let playbackMode: ReplayPlaybackMode

    public init(algorithmVersion: String, playbackMode: ReplayPlaybackMode = .frameByFrame) throws {
        guard !algorithmVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReplayValidationError.invalidAlgorithmVersion
        }

        if case .accelerated(let speed) = playbackMode {
            guard speed > 0, speed.isFinite else {
                throw ReplayValidationError.invalidPlaybackSpeed
            }
        }

        self.algorithmVersion = algorithmVersion
        self.playbackMode = playbackMode
    }
}

public struct ReplayExpectedEvent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case shot
        case targetLost
        case qualityWarning
    }

    public let id: String
    public let timestamp: TimeInterval
    public let kind: Kind
    public let normalizedImpact: NormalizedTargetCoordinate?
    public let notes: String?

    public init(
        id: String,
        timestamp: TimeInterval,
        kind: Kind,
        normalizedImpact: NormalizedTargetCoordinate? = nil,
        notes: String? = nil
    ) throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReplayValidationError.invalidExpectedEventID
        }

        guard timestamp >= 0, timestamp.isFinite else {
            throw ReplayValidationError.invalidExpectedEventTimestamp
        }

        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.normalizedImpact = normalizedImpact
        self.notes = notes
    }
}

public struct ReplayManifest: Codable, Equatable, Sendable {
    public let id: String
    public let targetDefinitionID: TargetDefinitionID?
    public let distance: Double?
    public let distanceUnit: DistanceUnit?
    public let caliber: String?
    public let notes: String?
    public let expectedEvents: [ReplayExpectedEvent]

    public init(
        id: String,
        targetDefinitionID: TargetDefinitionID? = nil,
        distance: Double? = nil,
        distanceUnit: DistanceUnit? = nil,
        caliber: String? = nil,
        notes: String? = nil,
        expectedEvents: [ReplayExpectedEvent] = []
    ) throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReplayValidationError.invalidManifestID
        }

        if let distance {
            guard distance > 0, distance.isFinite else {
                throw ReplayValidationError.invalidDistance
            }
        }

        self.id = id
        self.targetDefinitionID = targetDefinitionID
        self.distance = distance
        self.distanceUnit = distanceUnit
        self.caliber = caliber
        self.notes = notes
        self.expectedEvents = expectedEvents.sorted { $0.timestamp < $1.timestamp }
    }
}

public struct ReplayFrameResult: Codable, Equatable, Sendable {
    public let frame: VisionFrame
    public let events: [VisionPipelineEvent]

    public init(frame: VisionFrame, events: [VisionPipelineEvent]) {
        self.frame = frame
        self.events = events
    }
}

public enum ReplayCompletionReason: String, Codable, Equatable, Sendable {
    case endOfStream
    case cancelled
}

public struct ReplayRunResult: Codable, Equatable, Sendable {
    public let manifest: ReplayManifest
    public let configuration: ReplayRunConfiguration
    public let frameResults: [ReplayFrameResult]
    public let completionReason: ReplayCompletionReason

    public var processedFrameCount: Int {
        frameResults.count
    }
}

public struct ArrayReplayFrameSource: VisionFrameSource {
    private let frames: [VisionFrame]
    private var currentIndex = 0

    public init(frames: [VisionFrame]) throws {
        guard !frames.isEmpty else {
            throw ReplayValidationError.emptyFrameSequence
        }

        try Self.validate(frames)
        self.frames = frames
    }

    public mutating func nextFrame() async throws -> VisionFrame? {
        guard currentIndex < frames.count else {
            return nil
        }

        let frame = frames[currentIndex]
        currentIndex += 1
        return frame
    }

    private static func validate(_ frames: [VisionFrame]) throws {
        for pair in zip(frames, frames.dropFirst()) {
            guard pair.1.sequenceIndex > pair.0.sequenceIndex else {
                throw ReplayValidationError.nonIncreasingFrameSequence
            }

            guard pair.1.timestamp >= pair.0.timestamp else {
                throw ReplayValidationError.nonMonotonicFrameTimestamp
            }
        }
    }
}

public enum ReplayHarness {
    public static func run<Source: VisionFrameSource, Processor: VisionFrameProcessor>(
        manifest: ReplayManifest,
        configuration: ReplayRunConfiguration,
        frameSource: Source,
        processor: Processor
    ) async throws -> ReplayRunResult {
        var source = frameSource
        var frameProcessor = processor
        var frameResults: [ReplayFrameResult] = []

        while true {
            if Task.isCancelled {
                return ReplayRunResult(
                    manifest: manifest,
                    configuration: configuration,
                    frameResults: frameResults,
                    completionReason: .cancelled
                )
            }

            let frame: VisionFrame?

            do {
                frame = try await source.nextFrame()
            } catch is CancellationError {
                return ReplayRunResult(
                    manifest: manifest,
                    configuration: configuration,
                    frameResults: frameResults,
                    completionReason: .cancelled
                )
            }

            guard let frame else {
                return ReplayRunResult(
                    manifest: manifest,
                    configuration: configuration,
                    frameResults: frameResults,
                    completionReason: .endOfStream
                )
            }

            let events: [VisionPipelineEvent]

            do {
                events = try await frameProcessor.process(frame)
            } catch is CancellationError {
                return ReplayRunResult(
                    manifest: manifest,
                    configuration: configuration,
                    frameResults: frameResults,
                    completionReason: .cancelled
                )
            }

            frameResults.append(ReplayFrameResult(frame: frame, events: events))
        }
    }
}

public enum ReplayValidationError: Error, Equatable {
    case invalidAlgorithmVersion
    case invalidPlaybackSpeed
    case invalidExpectedEventID
    case invalidExpectedEventTimestamp
    case invalidManifestID
    case invalidDistance
    case emptyFrameSequence
    case nonIncreasingFrameSequence
    case nonMonotonicFrameTimestamp
}
