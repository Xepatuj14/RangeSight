import Foundation

public enum TargetIsolationStatus: String, Codable, Equatable, Sendable {
    case referenceReady
    case monitoring
    case skippedFrame
    case targetLost
    case invalidROI
}

public enum TargetLostReason: String, Codable, Equatable, Sendable {
    case invalidROI
    case insufficientTargetFeatures
    case sustainedRegistrationFailure
}

public struct TargetIsolationConfiguration: Codable, Equatable, Sendable {
    public let normalizedROIMargin: Double
    public let minimumROIDimensions: FrameDimensions
    public let maximumConsecutiveIdentityFailuresBeforeTargetLost: Int

    public init(
        normalizedROIMargin: Double = 0.015,
        minimumROIDimensions: FrameDimensions = LivePerformanceConfiguration.defaultMinimumROIDimensions,
        maximumConsecutiveIdentityFailuresBeforeTargetLost: Int = 3
    ) throws {
        guard normalizedROIMargin >= 0,
              normalizedROIMargin <= 0.05,
              normalizedROIMargin.isFinite,
              maximumConsecutiveIdentityFailuresBeforeTargetLost > 0 else {
            throw TargetIsolationValidationError.invalidConfiguration
        }

        self.normalizedROIMargin = normalizedROIMargin
        self.minimumROIDimensions = minimumROIDimensions
        self.maximumConsecutiveIdentityFailuresBeforeTargetLost = maximumConsecutiveIdentityFailuresBeforeTargetLost
    }

    public static let `default` = try! TargetIsolationConfiguration()
}

public struct TargetReferenceSignature: Codable, Equatable, Sendable {
    public let featureCount: Int
    public let averageLuminance: Double
    public let dimensions: FrameDimensions
    public let aspectRatio: Double

    public init(featureCount: Int, averageLuminance: Double, dimensions: FrameDimensions) throws {
        guard featureCount >= 0,
              averageLuminance.isFinite,
              (0...1).contains(averageLuminance) else {
            throw TargetIsolationValidationError.invalidReference
        }

        self.featureCount = featureCount
        self.averageLuminance = averageLuminance
        self.dimensions = dimensions
        self.aspectRatio = Double(dimensions.width) / Double(dimensions.height)
    }
}

public struct LockedTargetReference: Codable, Equatable, Sendable {
    public let id: String
    public let sourceQuadrilateral: TargetQuadrilateral
    public let analysisRegion: PixelRegion
    public let sourceDimensions: FrameDimensions
    public let baselineFrameSequenceIndex: Int
    public let baselineTimestamp: TimeInterval
    public let orientation: FrameOrientation
    public let perspective: PerspectiveNormalizationMetadata
    public let qualityMetrics: ImageQualityMetrics
    public let targetDefinitionID: TargetDefinitionID?
    public let registrationReference: RegistrationReferenceFrame
    public let baselineFrame: VisionFrame
    public let signature: TargetReferenceSignature

    public init(
        id: String,
        assessment: TargetLockAssessment,
        baselineFullFrame: VisionFrame,
        targetDefinitionID: TargetDefinitionID? = nil,
        configuration: TargetIsolationConfiguration = .default
    ) throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TargetIsolationValidationError.invalidReference
        }

        let region = try TargetROIMapper.pixelRegion(
            for: assessment.quadrilateral,
            sourceDimensions: baselineFullFrame.dimensions,
            minimumDimensions: configuration.minimumROIDimensions,
            normalizedMargin: configuration.normalizedROIMargin
        )
        let isolatedFrame = try TargetIsolationFrameExtractor.isolatedFrame(
            from: baselineFullFrame,
            region: region,
            sequenceIndex: baselineFullFrame.sequenceIndex,
            timestamp: baselineFullFrame.timestamp
        )
        let registrationReference = try RegistrationReferenceFrame(
            frame: isolatedFrame,
            minimumFeatureCount: FrameRegistrationConfiguration.default.minimumFeatureCount
        )
        let luminance = try TargetIsolationFrameExtractor.luminance(from: isolatedFrame)

        self.id = id
        self.sourceQuadrilateral = assessment.quadrilateral
        self.analysisRegion = region
        self.sourceDimensions = baselineFullFrame.dimensions
        self.baselineFrameSequenceIndex = baselineFullFrame.sequenceIndex
        self.baselineTimestamp = baselineFullFrame.timestamp
        self.orientation = baselineFullFrame.orientation
        self.perspective = assessment.perspective
        self.qualityMetrics = assessment.qualityMetrics
        self.targetDefinitionID = targetDefinitionID
        self.registrationReference = registrationReference
        self.baselineFrame = isolatedFrame
        self.signature = try TargetReferenceSignature(
            featureCount: registrationReference.features.count,
            averageLuminance: luminance.pixels.reduce(0, +) / Double(luminance.pixels.count),
            dimensions: isolatedFrame.dimensions
        )
    }
}

public struct TargetIsolationDiagnostics: Codable, Equatable, Sendable {
    public let lockID: String
    public let region: PixelRegion
    public let roiDimensions: FrameDimensions
    public let registrationConfidence: Double
    public let validOverlapRatio: Double
    public let consecutiveIdentityFailureCount: Int
    public let reLockCount: Int
    public let targetLostReason: TargetLostReason?

    public init(
        lockID: String,
        region: PixelRegion,
        roiDimensions: FrameDimensions,
        registrationConfidence: Double,
        validOverlapRatio: Double,
        consecutiveIdentityFailureCount: Int,
        reLockCount: Int,
        targetLostReason: TargetLostReason?
    ) {
        self.lockID = lockID
        self.region = region
        self.roiDimensions = roiDimensions
        self.registrationConfidence = registrationConfidence
        self.validOverlapRatio = validOverlapRatio
        self.consecutiveIdentityFailureCount = consecutiveIdentityFailureCount
        self.reLockCount = reLockCount
        self.targetLostReason = targetLostReason
    }

    public var visionDiagnostics: [VisionFrameDiagnostic] {
        [
            diagnostic("roiX", Double(region.x)),
            diagnostic("roiY", Double(region.y)),
            diagnostic("roiWidth", Double(region.width)),
            diagnostic("roiHeight", Double(region.height)),
            diagnostic("registrationConfidence", registrationConfidence),
            diagnostic("validOverlapRatio", validOverlapRatio),
            diagnostic("consecutiveIdentityFailures", Double(consecutiveIdentityFailureCount)),
            diagnostic("reLockCount", Double(reLockCount)),
            diagnostic("targetLostReason", targetLostReason.map(reasonCode) ?? 0)
        ].compactMap { $0 }
    }

    private func diagnostic(_ key: String, _ value: Double) -> VisionFrameDiagnostic? {
        try? VisionFrameDiagnostic(key: key, value: value)
    }

    private func reasonCode(_ reason: TargetLostReason) -> Double {
        switch reason {
        case .invalidROI: return 1
        case .insufficientTargetFeatures: return 2
        case .sustainedRegistrationFailure: return 3
        }
    }
}

public struct TargetIsolationFrameOutcome: Codable, Equatable, Sendable {
    public let status: TargetIsolationStatus
    public let frameSequenceIndex: Int
    public let frameTimestamp: TimeInterval
    public let isolatedFrame: VisionFrame?
    public let registration: FrameRegistrationResult?
    public let changeResult: ChangeDetectionResult?
    public let temporalResult: TemporalConfirmationResult?
    public let liveOutcome: LiveImpactFrameOutcome?
    public let diagnostics: TargetIsolationDiagnostics

    public var newImpactEvents: [LiveImpactEvent] {
        liveOutcome?.newEvents ?? []
    }
}

public struct TargetLostUserEscapes: Codable, Equatable, Sendable {
    public let canReLockTarget: Bool
    public let canEndString: Bool
    public let canLeaveSession: Bool

    public static let standard = TargetLostUserEscapes(
        canReLockTarget: true,
        canEndString: true,
        canLeaveSession: true
    )
}

public struct TargetIsolatedLiveImpactProcessor: Sendable {
    public private(set) var reference: LockedTargetReference
    public private(set) var consecutiveIdentityFailureCount: Int = 0
    public private(set) var reLockCount: Int = 0
    public private(set) var targetLostReason: TargetLostReason?
    public let targetLostEscapes = TargetLostUserEscapes.standard

    private let configuration: TargetIsolationConfiguration
    private let temporalConfiguration: TemporalConfirmationConfiguration
    private let registrationEngine: FrameRegistrationEngine
    private let changeDetector: FrameChangeDetector
    private var temporalConfirmer: TemporalImpactConfirmer
    private var liveSession: LiveImpactSession

    public init(
        reference: LockedTargetReference,
        configuration: TargetIsolationConfiguration = .default,
        registrationConfiguration: FrameRegistrationConfiguration = .default,
        changeDetectionConfiguration: ChangeDetectionConfiguration = .default,
        temporalConfiguration: TemporalConfirmationConfiguration = .default,
        audioAssistConfiguration: AudioAssistConfiguration? = nil,
        knownImpacts: [KnownImpact] = []
    ) {
        self.reference = reference
        self.configuration = configuration
        self.temporalConfiguration = temporalConfiguration
        self.registrationEngine = FrameRegistrationEngine(configuration: registrationConfiguration)
        self.changeDetector = FrameChangeDetector(configuration: changeDetectionConfiguration)
        self.temporalConfirmer = TemporalImpactConfirmer(configuration: temporalConfiguration, knownImpacts: knownImpacts)
        self.liveSession = LiveImpactSession(audioAssistConfiguration: audioAssistConfiguration)
        self.liveSession.startString()
    }

    public var isTargetLost: Bool {
        targetLostReason != nil
    }

    public mutating func recordAudioImpulse(_ candidate: AudioImpulseCandidate) {
        liveSession.recordAudioImpulse(candidate)
    }

    public mutating func endString() {
        liveSession.endString()
    }

    public mutating func reLockSameTarget(with newReference: LockedTargetReference) {
        reference = newReference
        consecutiveIdentityFailureCount = 0
        targetLostReason = nil
        reLockCount += 1
        let knownImpacts = temporalConfirmer.currentKnownImpacts
        temporalConfirmer = TemporalImpactConfirmer(configuration: temporalConfiguration, knownImpacts: knownImpacts)
    }

    public mutating func process(_ fullFrame: VisionFrame) throws -> TargetIsolationFrameOutcome {
        if let targetLostReason {
            return outcome(
                status: .targetLost,
                frame: fullFrame,
                isolatedFrame: nil,
                registration: nil,
                changeResult: nil,
                temporalResult: nil,
                liveOutcome: nil,
                targetLostReason: targetLostReason
            )
        }

        let isolatedFrame: VisionFrame
        do {
            isolatedFrame = try TargetIsolationFrameExtractor.isolatedFrame(
                from: fullFrame,
                region: reference.analysisRegion,
                sequenceIndex: fullFrame.sequenceIndex,
                timestamp: fullFrame.timestamp
            )
        } catch {
            return try markFailureAndOutcome(frame: fullFrame, reason: .invalidROI)
        }

        let registration = try registrationEngine.register(
            currentFrame: isolatedFrame,
            against: reference.registrationReference
        )
        guard registration.isUsableForChangeDetection else {
            let reason: TargetLostReason = registration.rejectionReason == .insufficientFeatures ? .insufficientTargetFeatures : .sustainedRegistrationFailure
            return try markFailureAndOutcome(
                frame: fullFrame,
                isolatedFrame: isolatedFrame,
                registration: registration,
                reason: reason
            )
        }

        consecutiveIdentityFailureCount = 0
        let changeResult = try changeDetector.detectChanges(
            referenceFrame: reference.baselineFrame,
            currentFrame: isolatedFrame,
            registration: registration
        )
        let temporalResult = try temporalConfirmer.process(changeResult)
        let liveOutcome = try liveSession.process(temporalResult)

        return outcome(
            status: .monitoring,
            frame: fullFrame,
            isolatedFrame: isolatedFrame,
            registration: registration,
            changeResult: changeResult,
            temporalResult: temporalResult,
            liveOutcome: liveOutcome,
            targetLostReason: nil
        )
    }

    private mutating func markFailureAndOutcome(
        frame: VisionFrame,
        isolatedFrame: VisionFrame? = nil,
        registration: FrameRegistrationResult? = nil,
        reason: TargetLostReason
    ) throws -> TargetIsolationFrameOutcome {
        consecutiveIdentityFailureCount += 1
        let shouldLoseTarget = consecutiveIdentityFailureCount >= configuration.maximumConsecutiveIdentityFailuresBeforeTargetLost
        if shouldLoseTarget {
            targetLostReason = reason
        }

        let changeResult = ChangeDetectionResult(
            status: .skippedDueToRegistration,
            frameSequenceIndex: frame.sequenceIndex,
            frameTimestamp: frame.timestamp,
            changedPixelRatio: 0,
            maximumMagnitude: 0,
            validComparisonPixelRatio: 0,
            candidates: [],
            registrationStatus: registration?.status ?? .invalidFrame
        )
        let temporalResult = try temporalConfirmer.process(changeResult)
        let liveOutcome = shouldLoseTarget ? nil : try liveSession.process(temporalResult)

        return outcome(
            status: shouldLoseTarget ? .targetLost : .skippedFrame,
            frame: frame,
            isolatedFrame: isolatedFrame,
            registration: registration,
            changeResult: changeResult,
            temporalResult: temporalResult,
            liveOutcome: liveOutcome,
            targetLostReason: shouldLoseTarget ? reason : nil
        )
    }

    private func outcome(
        status: TargetIsolationStatus,
        frame: VisionFrame,
        isolatedFrame: VisionFrame?,
        registration: FrameRegistrationResult?,
        changeResult: ChangeDetectionResult?,
        temporalResult: TemporalConfirmationResult?,
        liveOutcome: LiveImpactFrameOutcome?,
        targetLostReason: TargetLostReason?
    ) -> TargetIsolationFrameOutcome {
        TargetIsolationFrameOutcome(
            status: status,
            frameSequenceIndex: frame.sequenceIndex,
            frameTimestamp: frame.timestamp,
            isolatedFrame: isolatedFrame,
            registration: registration,
            changeResult: changeResult,
            temporalResult: temporalResult,
            liveOutcome: liveOutcome,
            diagnostics: TargetIsolationDiagnostics(
                lockID: reference.id,
                region: reference.analysisRegion,
                roiDimensions: FrameDimensions(rawWidth: reference.analysisRegion.width, rawHeight: reference.analysisRegion.height),
                registrationConfidence: registration?.confidence ?? 0,
                validOverlapRatio: changeResult?.validComparisonPixelRatio ?? 0,
                consecutiveIdentityFailureCount: consecutiveIdentityFailureCount,
                reLockCount: reLockCount,
                targetLostReason: targetLostReason
            )
        )
    }
}

public enum TargetIsolationFrameExtractor {
    public static func isolatedFrame(
        from frame: VisionFrame,
        region: PixelRegion,
        sequenceIndex: Int,
        timestamp: TimeInterval
    ) throws -> VisionFrame {
        let luminance = try luminance(from: frame)
        let extracted = try LuminanceROIExtractor.extract(
            from: luminance,
            region: region,
            minimumDimensions: try FrameDimensions(width: 1, height: 1)
        )
        guard let cropped = extracted.frame else {
            throw TargetIsolationValidationError.invalidFrameContent
        }

        let features = try remappedFeatures(from: frame, region: region)
        return try VisionFrame(
            sequenceIndex: sequenceIndex,
            timestamp: timestamp,
            dimensions: try FrameDimensions(width: cropped.width, height: cropped.height),
            orientation: frame.orientation,
            content: .fixtureRegisteredFrame(RegisteredFrameFixture(luminance: cropped, features: features))
        )
    }

    public static func luminance(from frame: VisionFrame) throws -> LuminanceFrame {
        switch frame.content {
        case .fixtureLuminance(let luminance):
            return luminance
        case .fixtureRegisteredFrame(let fixture):
            return fixture.luminance
        default:
            throw TargetIsolationValidationError.invalidFrameContent
        }
    }

    private static func remappedFeatures(from frame: VisionFrame, region: PixelRegion) throws -> [RegistrationFeature] {
        let features: [RegistrationFeature]
        switch frame.content {
        case .fixtureRegisteredFrame(let fixture):
            features = fixture.features
        case .fixtureFeatures(let fixtureFeatures):
            features = fixtureFeatures
        case .fixtureLuminance:
            features = []
        default:
            throw TargetIsolationValidationError.invalidFrameContent
        }

        return try features.compactMap { feature in
            let pixelX = feature.point.x * Double(frame.dimensions.width)
            let pixelY = feature.point.y * Double(frame.dimensions.height)
            guard pixelX >= Double(region.x),
                  pixelX < Double(region.maxXExclusive),
                  pixelY >= Double(region.y),
                  pixelY < Double(region.maxYExclusive) else {
                return nil
            }

            return try RegistrationFeature(
                id: feature.id,
                point: NormalizedImagePoint(
                    x: (pixelX - Double(region.x)) / Double(region.width),
                    y: (pixelY - Double(region.y)) / Double(region.height)
                )
            )
        }
    }
}

public enum TargetIsolationValidationError: Error, Equatable {
    case invalidConfiguration
    case invalidReference
    case invalidFrameContent
}

private extension FrameDimensions {
    init(rawWidth: Int, rawHeight: Int) {
        self = try! FrameDimensions(width: rawWidth, height: rawHeight)
    }
}
