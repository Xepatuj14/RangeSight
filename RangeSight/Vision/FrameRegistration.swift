import Foundation

public struct RegistrationFeature: Codable, Equatable, Sendable {
    public let id: String
    public let point: NormalizedImagePoint

    public init(id: String, point: NormalizedImagePoint) throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FrameRegistrationValidationError.invalidFeatureID
        }

        self.id = id
        self.point = point
    }
}

public struct RegistrationReferenceFrame: Codable, Equatable, Sendable {
    public let frameSequenceIndex: Int
    public let frameTimestamp: TimeInterval
    public let dimensions: FrameDimensions
    public let orientation: FrameOrientation
    public let features: [RegistrationFeature]

    public init(frame: VisionFrame, minimumFeatureCount: Int) throws {
        let features = try FrameRegistrationFeatureExtractor.features(from: frame)
        guard features.count >= minimumFeatureCount else {
            throw FrameRegistrationValidationError.insufficientFeatures
        }

        self.frameSequenceIndex = frame.sequenceIndex
        self.frameTimestamp = frame.timestamp
        self.dimensions = frame.dimensions
        self.orientation = frame.orientation
        self.features = features
    }
}

public struct RegistrationTransform: Codable, Equatable, Sendable {
    /// Maps normalized current-frame coordinates into normalized reference-frame coordinates.
    ///
    /// Pixel resampling must use the inverse mapping when constructing an aligned current image
    /// in reference-frame coordinates.
    public let translationX: Double
    public let translationY: Double
    public let rotationRadians: Double
    public let scale: Double

    public init(translationX: Double, translationY: Double, rotationRadians: Double, scale: Double) throws {
        guard translationX.isFinite, translationY.isFinite, rotationRadians.isFinite, scale.isFinite, scale > 0 else {
            throw FrameRegistrationValidationError.invalidTransform
        }

        self.translationX = translationX
        self.translationY = translationY
        self.rotationRadians = rotationRadians
        self.scale = scale
    }

    public static let identity = try! RegistrationTransform(
        translationX: 0,
        translationY: 0,
        rotationRadians: 0,
        scale: 1
    )

    public func applying(to point: NormalizedImagePoint) throws -> NormalizedImagePoint {
        let cosine = cos(rotationRadians)
        let sine = sin(rotationRadians)
        let x = scale * (cosine * point.x - sine * point.y) + translationX
        let y = scale * (sine * point.x + cosine * point.y) + translationY
        return try NormalizedImagePoint(x: x, y: y)
    }
}

public enum FrameRegistrationStatus: String, Codable, Equatable, Sendable {
    case referenceReady
    case registered
    case lowConfidence
    case failed
    case referenceUnavailable
    case invalidFrame
}

public enum FrameRegistrationRejectionReason: String, Codable, Equatable, Sendable {
    case incompatibleDimensions
    case incompatibleOrientation
    case insufficientFeatures
    case transformCannotBeEstimated
    case excessiveMotion
    case qualityBelowThreshold
    case invalidFrameContent
}

public struct FrameRegistrationConfiguration: Codable, Equatable, Sendable {
    public let minimumFeatureCount: Int
    public let maximumRootMeanSquareError: Double
    public let minimumConfidence: Double
    public let maximumTranslation: Double
    public let maximumRotationRadians: Double
    public let minimumScale: Double
    public let maximumScale: Double

    public init(
        minimumFeatureCount: Int = 3,
        maximumRootMeanSquareError: Double = 0.025,
        minimumConfidence: Double = 0.65,
        maximumTranslation: Double = 0.18,
        maximumRotationRadians: Double = 0.2,
        minimumScale: Double = 0.9,
        maximumScale: Double = 1.1
    ) throws {
        guard minimumFeatureCount >= 2 else {
            throw FrameRegistrationValidationError.invalidConfiguration
        }
        guard maximumRootMeanSquareError > 0, maximumRootMeanSquareError.isFinite else {
            throw FrameRegistrationValidationError.invalidConfiguration
        }
        guard (0...1).contains(minimumConfidence) else {
            throw FrameRegistrationValidationError.invalidConfiguration
        }
        guard maximumTranslation > 0, maximumTranslation.isFinite else {
            throw FrameRegistrationValidationError.invalidConfiguration
        }
        guard maximumRotationRadians > 0, maximumRotationRadians.isFinite else {
            throw FrameRegistrationValidationError.invalidConfiguration
        }
        guard minimumScale > 0, maximumScale >= minimumScale else {
            throw FrameRegistrationValidationError.invalidConfiguration
        }

        self.minimumFeatureCount = minimumFeatureCount
        self.maximumRootMeanSquareError = maximumRootMeanSquareError
        self.minimumConfidence = minimumConfidence
        self.maximumTranslation = maximumTranslation
        self.maximumRotationRadians = maximumRotationRadians
        self.minimumScale = minimumScale
        self.maximumScale = maximumScale
    }

    public static let `default` = try! FrameRegistrationConfiguration()
}

public struct FrameRegistrationResult: Codable, Equatable, Sendable {
    public let status: FrameRegistrationStatus
    public let referenceFrameSequenceIndex: Int?
    public let currentFrameSequenceIndex: Int
    public let transform: RegistrationTransform?
    public let confidence: Double
    public let rootMeanSquareError: Double?
    public let matchedFeatureCount: Int
    public let rejectionReason: FrameRegistrationRejectionReason?

    public var isUsableForChangeDetection: Bool {
        status == .registered
    }
}

public enum FrameRegistrationFeatureExtractor {
    public static func features(from frame: VisionFrame) throws -> [RegistrationFeature] {
        switch frame.content {
        case .fixtureFeatures(let features):
            return features
        case .fixtureRegisteredFrame(let fixture):
            return fixture.features
        default:
            throw FrameRegistrationValidationError.invalidFrameContent
        }
    }
}

public struct FrameRegistrationEngine: Sendable {
    public let configuration: FrameRegistrationConfiguration

    public init(configuration: FrameRegistrationConfiguration = .default) {
        self.configuration = configuration
    }

    public func register(
        currentFrame: VisionFrame,
        against reference: RegistrationReferenceFrame?
    ) throws -> FrameRegistrationResult {
        guard let reference else {
            return failure(
                status: .referenceUnavailable,
                currentFrame: currentFrame,
                referenceFrameSequenceIndex: nil,
                reason: nil
            )
        }

        guard currentFrame.dimensions == reference.dimensions else {
            return failure(
                currentFrame: currentFrame,
                referenceFrameSequenceIndex: reference.frameSequenceIndex,
                reason: .incompatibleDimensions
            )
        }

        guard currentFrame.orientation == reference.orientation else {
            return failure(
                currentFrame: currentFrame,
                referenceFrameSequenceIndex: reference.frameSequenceIndex,
                reason: .incompatibleOrientation
            )
        }

        let currentFeatures: [RegistrationFeature]

        do {
            currentFeatures = try FrameRegistrationFeatureExtractor.features(from: currentFrame)
        } catch {
            return failure(
                status: .invalidFrame,
                currentFrame: currentFrame,
                referenceFrameSequenceIndex: reference.frameSequenceIndex,
                reason: .invalidFrameContent
            )
        }

        let pairs = matchedPairs(reference: reference.features, current: currentFeatures)
        guard pairs.count >= configuration.minimumFeatureCount else {
            return failure(
                currentFrame: currentFrame,
                referenceFrameSequenceIndex: reference.frameSequenceIndex,
                matchedFeatureCount: pairs.count,
                reason: .insufficientFeatures
            )
        }

        guard let transform = try estimateTransform(from: pairs) else {
            return failure(
                currentFrame: currentFrame,
                referenceFrameSequenceIndex: reference.frameSequenceIndex,
                matchedFeatureCount: pairs.count,
                reason: .transformCannotBeEstimated
            )
        }

        let rmsError = try rootMeanSquareError(transform: transform, pairs: pairs)
        let confidence = max(0, min(1, 1 - rmsError / configuration.maximumRootMeanSquareError))
        let translationMagnitude = hypot(transform.translationX, transform.translationY)

        guard translationMagnitude <= configuration.maximumTranslation,
              abs(transform.rotationRadians) <= configuration.maximumRotationRadians,
              (configuration.minimumScale...configuration.maximumScale).contains(transform.scale) else {
            return FrameRegistrationResult(
                status: .failed,
                referenceFrameSequenceIndex: reference.frameSequenceIndex,
                currentFrameSequenceIndex: currentFrame.sequenceIndex,
                transform: transform,
                confidence: confidence,
                rootMeanSquareError: rmsError,
                matchedFeatureCount: pairs.count,
                rejectionReason: .excessiveMotion
            )
        }

        if confidence < configuration.minimumConfidence {
            return FrameRegistrationResult(
                status: .lowConfidence,
                referenceFrameSequenceIndex: reference.frameSequenceIndex,
                currentFrameSequenceIndex: currentFrame.sequenceIndex,
                transform: transform,
                confidence: confidence,
                rootMeanSquareError: rmsError,
                matchedFeatureCount: pairs.count,
                rejectionReason: .qualityBelowThreshold
            )
        }

        return FrameRegistrationResult(
            status: .registered,
            referenceFrameSequenceIndex: reference.frameSequenceIndex,
            currentFrameSequenceIndex: currentFrame.sequenceIndex,
            transform: transform,
            confidence: confidence,
            rootMeanSquareError: rmsError,
            matchedFeatureCount: pairs.count,
            rejectionReason: nil
        )
    }

    private func failure(
        status: FrameRegistrationStatus = .failed,
        currentFrame: VisionFrame,
        referenceFrameSequenceIndex: Int?,
        matchedFeatureCount: Int = 0,
        reason: FrameRegistrationRejectionReason?
    ) -> FrameRegistrationResult {
        FrameRegistrationResult(
            status: status,
            referenceFrameSequenceIndex: referenceFrameSequenceIndex,
            currentFrameSequenceIndex: currentFrame.sequenceIndex,
            transform: nil,
            confidence: 0,
            rootMeanSquareError: nil,
            matchedFeatureCount: matchedFeatureCount,
            rejectionReason: reason
        )
    }

    private func matchedPairs(
        reference: [RegistrationFeature],
        current: [RegistrationFeature]
    ) -> [(reference: NormalizedImagePoint, current: NormalizedImagePoint)] {
        var referenceByID: [String: NormalizedImagePoint] = [:]

        for feature in reference where referenceByID[feature.id] == nil {
            referenceByID[feature.id] = feature.point
        }

        return current.compactMap { feature in
            guard let referencePoint = referenceByID[feature.id] else {
                return nil
            }

            return (reference: referencePoint, current: feature.point)
        }
    }

    private func estimateTransform(
        from pairs: [(reference: NormalizedImagePoint, current: NormalizedImagePoint)]
    ) throws -> RegistrationTransform? {
        let referenceCenter = centroid(pairs.map { $0.reference })
        let currentCenter = centroid(pairs.map { $0.current })
        var numeratorA = 0.0
        var numeratorB = 0.0
        var denominator = 0.0

        for pair in pairs {
            let currentX = pair.current.x - currentCenter.x
            let currentY = pair.current.y - currentCenter.y
            let referenceX = pair.reference.x - referenceCenter.x
            let referenceY = pair.reference.y - referenceCenter.y

            numeratorA += currentX * referenceX + currentY * referenceY
            numeratorB += currentX * referenceY - currentY * referenceX
            denominator += currentX * currentX + currentY * currentY
        }

        guard denominator > 0 else {
            return nil
        }

        let scale = sqrt(numeratorA * numeratorA + numeratorB * numeratorB) / denominator
        guard scale > 0, scale.isFinite else {
            return nil
        }

        let rotation = atan2(numeratorB, numeratorA)
        let cosine = cos(rotation)
        let sine = sin(rotation)
        let transformedCurrentCenterX = scale * (cosine * currentCenter.x - sine * currentCenter.y)
        let transformedCurrentCenterY = scale * (sine * currentCenter.x + cosine * currentCenter.y)

        return try RegistrationTransform(
            translationX: referenceCenter.x - transformedCurrentCenterX,
            translationY: referenceCenter.y - transformedCurrentCenterY,
            rotationRadians: rotation,
            scale: scale
        )
    }

    private func rootMeanSquareError(
        transform: RegistrationTransform,
        pairs: [(reference: NormalizedImagePoint, current: NormalizedImagePoint)]
    ) throws -> Double {
        let squaredError = try pairs.reduce(0.0) { partial, pair in
            let aligned = try transform.applying(to: pair.current)
            return partial + pow(aligned.x - pair.reference.x, 2) + pow(aligned.y - pair.reference.y, 2)
        }

        return sqrt(squaredError / Double(pairs.count))
    }

    private func centroid(_ points: [NormalizedImagePoint]) -> (x: Double, y: Double) {
        let count = Double(points.count)
        return (
            x: points.reduce(0) { $0 + $1.x } / count,
            y: points.reduce(0) { $0 + $1.y } / count
        )
    }
}

public struct FrameRegistrationProcessor: VisionFrameProcessor {
    private let engine: FrameRegistrationEngine
    private let configuration: FrameRegistrationConfiguration
    private var reference: RegistrationReferenceFrame?

    public init(configuration: FrameRegistrationConfiguration = .default) {
        self.configuration = configuration
        self.engine = FrameRegistrationEngine(configuration: configuration)
    }

    public mutating func process(_ frame: VisionFrame) async throws -> [VisionPipelineEvent] {
        if reference == nil {
            do {
                reference = try RegistrationReferenceFrame(
                    frame: frame,
                    minimumFeatureCount: configuration.minimumFeatureCount
                )

                return [
                    try registrationEvent(
                        frame: frame,
                        result: FrameRegistrationResult(
                            status: .referenceReady,
                            referenceFrameSequenceIndex: frame.sequenceIndex,
                            currentFrameSequenceIndex: frame.sequenceIndex,
                            transform: .identity,
                            confidence: 1,
                            rootMeanSquareError: 0,
                            matchedFeatureCount: reference?.features.count ?? 0,
                            rejectionReason: nil
                        )
                    )
                ]
            } catch {
                return [
                    try registrationEvent(
                        frame: frame,
                        result: FrameRegistrationResult(
                            status: .invalidFrame,
                            referenceFrameSequenceIndex: nil,
                            currentFrameSequenceIndex: frame.sequenceIndex,
                            transform: nil,
                            confidence: 0,
                            rootMeanSquareError: nil,
                            matchedFeatureCount: 0,
                            rejectionReason: .invalidFrameContent
                        )
                    )
                ]
            }
        }

        let result = try engine.register(currentFrame: frame, against: reference)
        return [try registrationEvent(frame: frame, result: result)]
    }

    private func registrationEvent(frame: VisionFrame, result: FrameRegistrationResult) throws -> VisionPipelineEvent {
        VisionPipelineEvent(
            frameSequenceIndex: frame.sequenceIndex,
            frameTimestamp: frame.timestamp,
            stage: .frameRegistration,
            diagnostics: try FrameRegistrationDiagnostics.diagnostics(for: result)
        )
    }
}

public enum FrameRegistrationDiagnostics {
    public static func diagnostics(for result: FrameRegistrationResult) throws -> [VisionFrameDiagnostic] {
        var diagnostics = [
            try VisionFrameDiagnostic(key: "registrationStatus", value: statusCodeForDiagnostics(result.status)),
            try VisionFrameDiagnostic(key: "registrationConfidence", value: result.confidence),
            try VisionFrameDiagnostic(key: "matchedFeatureCount", value: Double(result.matchedFeatureCount))
        ]

        if let rootMeanSquareError = result.rootMeanSquareError {
            diagnostics.append(try VisionFrameDiagnostic(key: "registrationRMSError", value: rootMeanSquareError))
        }

        if let transform = result.transform {
            diagnostics.append(contentsOf: [
                try VisionFrameDiagnostic(key: "translationX", value: transform.translationX),
                try VisionFrameDiagnostic(key: "translationY", value: transform.translationY),
                try VisionFrameDiagnostic(key: "rotationRadians", value: transform.rotationRadians),
                try VisionFrameDiagnostic(key: "scale", value: transform.scale)
            ])
        }

        if let rejectionReason = result.rejectionReason {
            diagnostics.append(try VisionFrameDiagnostic(key: "rejectionReason", value: rejectionCode(rejectionReason)))
        }

        if let referenceFrameSequenceIndex = result.referenceFrameSequenceIndex {
            diagnostics.append(try VisionFrameDiagnostic(key: "referenceFrameIndex", value: Double(referenceFrameSequenceIndex)))
        }

        return diagnostics
    }

    public static func statusCodeForDiagnostics(_ status: FrameRegistrationStatus) -> Double {
        switch status {
        case .referenceReady: return 1
        case .registered: return 2
        case .lowConfidence: return 3
        case .failed: return 4
        case .referenceUnavailable: return 5
        case .invalidFrame: return 6
        }
    }

    private static func rejectionCode(_ reason: FrameRegistrationRejectionReason) -> Double {
        switch reason {
        case .incompatibleDimensions: return 1
        case .incompatibleOrientation: return 2
        case .insufficientFeatures: return 3
        case .transformCannotBeEstimated: return 4
        case .excessiveMotion: return 5
        case .qualityBelowThreshold: return 6
        case .invalidFrameContent: return 7
        }
    }
}

public enum FrameRegistrationValidationError: Error, Equatable {
    case invalidFeatureID
    case invalidFrameContent
    case insufficientFeatures
    case invalidTransform
    case invalidConfiguration
}
