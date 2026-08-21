import Foundation

public struct LuminanceFrame: Codable, Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [Double]

    public init(width: Int, height: Int, pixels: [Double]) throws {
        guard width > 0, height > 0, pixels.count == width * height else {
            throw FrameChangeDetectionValidationError.invalidPixelBuffer
        }

        guard pixels.allSatisfy({ (0...1).contains($0) && $0.isFinite }) else {
            throw FrameChangeDetectionValidationError.invalidLuminanceValue
        }

        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public func luminanceAt(x: Int, y: Int) -> Double {
        pixels[y * width + x]
    }
}

public struct AlignedLuminanceFrame: Codable, Equatable, Sendable {
    public let luminance: LuminanceFrame
    public let validPixels: [Bool]

    public init(luminance: LuminanceFrame, validPixels: [Bool]) throws {
        guard validPixels.count == luminance.width * luminance.height else {
            throw FrameChangeDetectionValidationError.invalidValidityMask
        }

        self.luminance = luminance
        self.validPixels = validPixels
    }

    public var validPixelCount: Int {
        validPixels.reduce(0) { $0 + ($1 ? 1 : 0) }
    }

    public var overlapRatio: Double {
        Double(validPixelCount) / Double(validPixels.count)
    }
}

public struct NormalizedImageRegion: Codable, Equatable, Sendable {
    public let minX: Double
    public let minY: Double
    public let maxX: Double
    public let maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) throws {
        guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite,
              0 <= minX, minX <= maxX, maxX <= 1,
              0 <= minY, minY <= maxY, maxY <= 1 else {
            throw FrameChangeDetectionValidationError.invalidRegion
        }

        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public var width: Double {
        maxX - minX
    }

    public var height: Double {
        maxY - minY
    }
}

public struct ChangeCandidate: Codable, Equatable, Sendable {
    public let id: String
    public let frameSequenceIndex: Int
    public let frameTimestamp: TimeInterval
    public let bounds: NormalizedImageRegion
    public let centroid: NormalizedImagePoint
    public let areaPixels: Int
    public let magnitude: Double
    public let contrast: Double
    public let registrationConfidence: Double

    public init(
        id: String,
        frameSequenceIndex: Int,
        frameTimestamp: TimeInterval,
        bounds: NormalizedImageRegion,
        centroid: NormalizedImagePoint,
        areaPixels: Int,
        magnitude: Double,
        contrast: Double,
        registrationConfidence: Double
    ) throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FrameChangeDetectionValidationError.invalidCandidateID
        }
        guard areaPixels > 0 else {
            throw FrameChangeDetectionValidationError.invalidRegionArea
        }
        guard magnitude.isFinite, magnitude >= 0,
              contrast.isFinite, contrast >= 0,
              (0...1).contains(registrationConfidence) else {
            throw FrameChangeDetectionValidationError.invalidMetric
        }

        self.id = id
        self.frameSequenceIndex = frameSequenceIndex
        self.frameTimestamp = frameTimestamp
        self.bounds = bounds
        self.centroid = centroid
        self.areaPixels = areaPixels
        self.magnitude = magnitude
        self.contrast = contrast
        self.registrationConfidence = registrationConfidence
    }
}

public enum ChangeDetectionStatus: String, Codable, Equatable, Sendable {
    case noChange
    case localizedChangeDetected
    case globalChangeRejected
    case skippedDueToRegistration
    case invalidFrame
}

public struct ChangeDetectionConfiguration: Codable, Equatable, Sendable {
    public let pixelDifferenceThreshold: Double
    public let minimumRegionAreaPixels: Int
    public let maximumRegionAreaRatio: Double
    public let globalChangePixelRatio: Double
    public let minimumValidOverlapRatio: Double

    public init(
        pixelDifferenceThreshold: Double = 0.18,
        minimumRegionAreaPixels: Int = 2,
        maximumRegionAreaRatio: Double = 0.2,
        globalChangePixelRatio: Double = 0.45,
        minimumValidOverlapRatio: Double = 0.5
    ) throws {
        guard (0...1).contains(pixelDifferenceThreshold), pixelDifferenceThreshold > 0 else {
            throw FrameChangeDetectionValidationError.invalidConfiguration
        }
        guard minimumRegionAreaPixels > 0 else {
            throw FrameChangeDetectionValidationError.invalidConfiguration
        }
        guard (0...1).contains(maximumRegionAreaRatio), maximumRegionAreaRatio > 0 else {
            throw FrameChangeDetectionValidationError.invalidConfiguration
        }
        guard (0...1).contains(globalChangePixelRatio), globalChangePixelRatio > 0 else {
            throw FrameChangeDetectionValidationError.invalidConfiguration
        }
        guard (0...1).contains(minimumValidOverlapRatio), minimumValidOverlapRatio > 0 else {
            throw FrameChangeDetectionValidationError.invalidConfiguration
        }

        self.pixelDifferenceThreshold = pixelDifferenceThreshold
        self.minimumRegionAreaPixels = minimumRegionAreaPixels
        self.maximumRegionAreaRatio = maximumRegionAreaRatio
        self.globalChangePixelRatio = globalChangePixelRatio
        self.minimumValidOverlapRatio = minimumValidOverlapRatio
    }

    public static let `default` = try! ChangeDetectionConfiguration()
}

public struct ChangeDetectionResult: Codable, Equatable, Sendable {
    public let status: ChangeDetectionStatus
    public let frameSequenceIndex: Int
    public let frameTimestamp: TimeInterval
    public let changedPixelRatio: Double
    public let maximumMagnitude: Double
    public let validComparisonPixelRatio: Double
    public let candidates: [ChangeCandidate]
    public let registrationStatus: FrameRegistrationStatus

    public init(
        status: ChangeDetectionStatus,
        frameSequenceIndex: Int,
        frameTimestamp: TimeInterval,
        changedPixelRatio: Double,
        maximumMagnitude: Double,
        validComparisonPixelRatio: Double = 1,
        candidates: [ChangeCandidate],
        registrationStatus: FrameRegistrationStatus
    ) {
        self.status = status
        self.frameSequenceIndex = frameSequenceIndex
        self.frameTimestamp = frameTimestamp
        self.changedPixelRatio = changedPixelRatio
        self.maximumMagnitude = maximumMagnitude
        self.validComparisonPixelRatio = validComparisonPixelRatio
        self.candidates = candidates
        self.registrationStatus = registrationStatus
    }

    public var hasLocalizedCandidates: Bool {
        !candidates.isEmpty
    }
}

public struct FrameChangeDetector: Sendable {
    public let configuration: ChangeDetectionConfiguration

    public init(configuration: ChangeDetectionConfiguration = .default) {
        self.configuration = configuration
    }

    public func detectChanges(
        referenceFrame: VisionFrame,
        currentFrame: VisionFrame,
        registration: FrameRegistrationResult
    ) throws -> ChangeDetectionResult {
        guard registration.isUsableForChangeDetection else {
            return ChangeDetectionResult(
                status: .skippedDueToRegistration,
                frameSequenceIndex: currentFrame.sequenceIndex,
                frameTimestamp: currentFrame.timestamp,
                changedPixelRatio: 0,
                maximumMagnitude: 0,
                validComparisonPixelRatio: 0,
                candidates: [],
                registrationStatus: registration.status
            )
        }

        guard let transform = registration.transform else {
            return ChangeDetectionResult(
                status: .invalidFrame,
                frameSequenceIndex: currentFrame.sequenceIndex,
                frameTimestamp: currentFrame.timestamp,
                changedPixelRatio: 0,
                maximumMagnitude: 0,
                validComparisonPixelRatio: 0,
                candidates: [],
                registrationStatus: registration.status
            )
        }

        guard let reference = try luminanceContent(from: referenceFrame),
              let current = try luminanceContent(from: currentFrame),
              reference.width == current.width,
              reference.height == current.height else {
            return ChangeDetectionResult(
                status: .invalidFrame,
                frameSequenceIndex: currentFrame.sequenceIndex,
                frameTimestamp: currentFrame.timestamp,
                changedPixelRatio: 0,
                maximumMagnitude: 0,
                validComparisonPixelRatio: 0,
                candidates: [],
                registrationStatus: registration.status
            )
        }

        let alignedCurrent = try align(current: current, intoReferenceCoordinatesUsing: transform)
        let validPixelCount = alignedCurrent.validPixelCount
        let validPixelRatio = alignedCurrent.overlapRatio
        guard validPixelRatio >= configuration.minimumValidOverlapRatio, validPixelCount > 0 else {
            return ChangeDetectionResult(
                status: .skippedDueToRegistration,
                frameSequenceIndex: currentFrame.sequenceIndex,
                frameTimestamp: currentFrame.timestamp,
                changedPixelRatio: 0,
                maximumMagnitude: 0,
                validComparisonPixelRatio: validPixelRatio,
                candidates: [],
                registrationStatus: registration.status
            )
        }

        let totalPixels = reference.width * reference.height
        var changed = Array(repeating: false, count: totalPixels)
        var changedCount = 0
        var maximumMagnitude = 0.0

        for index in 0..<totalPixels {
            guard alignedCurrent.validPixels[index] else {
                continue
            }

            let magnitude = abs(alignedCurrent.luminance.pixels[index] - reference.pixels[index])
            maximumMagnitude = max(maximumMagnitude, magnitude)

            if magnitude >= configuration.pixelDifferenceThreshold {
                changed[index] = true
                changedCount += 1
            }
        }

        let changedRatio = Double(changedCount) / Double(validPixelCount)
        guard changedRatio < configuration.globalChangePixelRatio else {
            return ChangeDetectionResult(
                status: .globalChangeRejected,
                frameSequenceIndex: currentFrame.sequenceIndex,
                frameTimestamp: currentFrame.timestamp,
                changedPixelRatio: changedRatio,
                maximumMagnitude: maximumMagnitude,
                validComparisonPixelRatio: validPixelRatio,
                candidates: [],
                registrationStatus: registration.status
            )
        }

        let candidates = try connectedComponents(
            changed: changed,
            reference: reference,
            current: alignedCurrent.luminance,
            frame: currentFrame,
            registration: registration
        )

        return ChangeDetectionResult(
            status: candidates.isEmpty ? .noChange : .localizedChangeDetected,
            frameSequenceIndex: currentFrame.sequenceIndex,
            frameTimestamp: currentFrame.timestamp,
            changedPixelRatio: changedRatio,
            maximumMagnitude: maximumMagnitude,
            validComparisonPixelRatio: validPixelRatio,
            candidates: candidates,
            registrationStatus: registration.status
        )
    }

    private func luminanceContent(from frame: VisionFrame) throws -> LuminanceFrame? {
        let luminanceFrame: LuminanceFrame

        switch frame.content {
        case .fixtureLuminance(let frame):
            luminanceFrame = frame
        case .fixtureRegisteredFrame(let fixture):
            luminanceFrame = fixture.luminance
        default:
            return nil
        }

        guard frame.dimensions.width == luminanceFrame.width,
              frame.dimensions.height == luminanceFrame.height else {
            throw FrameChangeDetectionValidationError.incompatibleDimensions
        }

        return luminanceFrame
    }

    private func align(
        current: LuminanceFrame,
        intoReferenceCoordinatesUsing transform: RegistrationTransform
    ) throws -> AlignedLuminanceFrame {
        var alignedPixels = Array(repeating: 0.0, count: current.width * current.height)
        var validPixels = Array(repeating: false, count: current.width * current.height)

        for y in 0..<current.height {
            for x in 0..<current.width {
                let referenceX = (Double(x) + 0.5) / Double(current.width)
                let referenceY = (Double(y) + 0.5) / Double(current.height)
                let currentPoint = inverseApply(transform: transform, referenceX: referenceX, referenceY: referenceY)

                guard (0...1).contains(currentPoint.x), (0...1).contains(currentPoint.y),
                      let sampled = bilinearSample(current, normalizedX: currentPoint.x, normalizedY: currentPoint.y) else {
                    continue
                }

                let index = y * current.width + x
                alignedPixels[index] = sampled
                validPixels[index] = true
            }
        }

        return try AlignedLuminanceFrame(
            luminance: try LuminanceFrame(width: current.width, height: current.height, pixels: alignedPixels),
            validPixels: validPixels
        )
    }

    private func inverseApply(
        transform: RegistrationTransform,
        referenceX: Double,
        referenceY: Double
    ) -> (x: Double, y: Double) {
        let translatedX = (referenceX - transform.translationX) / transform.scale
        let translatedY = (referenceY - transform.translationY) / transform.scale
        let cosine = cos(transform.rotationRadians)
        let sine = sin(transform.rotationRadians)

        return (
            x: cosine * translatedX + sine * translatedY,
            y: -sine * translatedX + cosine * translatedY
        )
    }

    private func bilinearSample(_ frame: LuminanceFrame, normalizedX: Double, normalizedY: Double) -> Double? {
        let pixelX = normalizedX * Double(frame.width) - 0.5
        let pixelY = normalizedY * Double(frame.height) - 0.5

        guard pixelX >= 0, pixelX <= Double(frame.width - 1),
              pixelY >= 0, pixelY <= Double(frame.height - 1) else {
            return nil
        }

        let x0 = Int(floor(pixelX))
        let y0 = Int(floor(pixelY))
        let x1 = min(x0 + 1, frame.width - 1)
        let y1 = min(y0 + 1, frame.height - 1)
        let tx = pixelX - Double(x0)
        let ty = pixelY - Double(y0)

        let top = frame.luminanceAt(x: x0, y: y0) * (1 - tx) + frame.luminanceAt(x: x1, y: y0) * tx
        let bottom = frame.luminanceAt(x: x0, y: y1) * (1 - tx) + frame.luminanceAt(x: x1, y: y1) * tx
        return top * (1 - ty) + bottom * ty
    }

    private func connectedComponents(
        changed: [Bool],
        reference: LuminanceFrame,
        current: LuminanceFrame,
        frame: VisionFrame,
        registration: FrameRegistrationResult
    ) throws -> [ChangeCandidate] {
        var visited = Array(repeating: false, count: changed.count)
        var candidates: [ChangeCandidate] = []
        let maximumRegionArea = Int(Double(changed.count) * configuration.maximumRegionAreaRatio)

        for index in changed.indices where changed[index] && !visited[index] {
            var queue = [index]
            visited[index] = true
            var component: [Int] = []

            while let pixel = queue.popLast() {
                component.append(pixel)

                for neighbor in neighbors(of: pixel, width: current.width, height: current.height)
                where changed[neighbor] && !visited[neighbor] {
                    visited[neighbor] = true
                    queue.append(neighbor)
                }
            }

            guard component.count >= configuration.minimumRegionAreaPixels,
                  component.count <= maximumRegionArea else {
                continue
            }

            candidates.append(try candidate(
                id: "change-\(frame.sequenceIndex)-\(candidates.count + 1)",
                component: component,
                reference: reference,
                current: current,
                frame: frame,
                registration: registration
            ))
        }

        return candidates.sorted {
            if $0.centroid.y == $1.centroid.y {
                return $0.centroid.x < $1.centroid.x
            }

            return $0.centroid.y < $1.centroid.y
        }
    }

    private func neighbors(of index: Int, width: Int, height: Int) -> [Int] {
        let x = index % width
        let y = index / width
        var neighbors: [Int] = []

        if x > 0 { neighbors.append(index - 1) }
        if x < width - 1 { neighbors.append(index + 1) }
        if y > 0 { neighbors.append(index - width) }
        if y < height - 1 { neighbors.append(index + width) }

        return neighbors
    }

    private func candidate(
        id: String,
        component: [Int],
        reference: LuminanceFrame,
        current: LuminanceFrame,
        frame: VisionFrame,
        registration: FrameRegistrationResult
    ) throws -> ChangeCandidate {
        var minX = current.width
        var minY = current.height
        var maxX = 0
        var maxY = 0
        var sumX = 0.0
        var sumY = 0.0
        var magnitudeSum = 0.0

        for index in component {
            let x = index % current.width
            let y = index / current.width
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
            sumX += Double(x) + 0.5
            sumY += Double(y) + 0.5
            magnitudeSum += abs(current.pixels[index] - reference.pixels[index])
        }

        let area = component.count
        let magnitude = magnitudeSum / Double(area)
        let centroid = try NormalizedImagePoint(
            x: sumX / Double(area) / Double(current.width),
            y: sumY / Double(area) / Double(current.height)
        )
        let bounds = try NormalizedImageRegion(
            minX: Double(minX) / Double(current.width),
            minY: Double(minY) / Double(current.height),
            maxX: Double(maxX + 1) / Double(current.width),
            maxY: Double(maxY + 1) / Double(current.height)
        )

        return try ChangeCandidate(
            id: id,
            frameSequenceIndex: frame.sequenceIndex,
            frameTimestamp: frame.timestamp,
            bounds: bounds,
            centroid: centroid,
            areaPixels: area,
            magnitude: magnitude,
            contrast: magnitude,
            registrationConfidence: registration.confidence
        )
    }
}

public struct RegisteredChangeDetectionProcessor: VisionFrameProcessor {
    private let registrationConfiguration: FrameRegistrationConfiguration
    private let changeDetector: FrameChangeDetector
    private let registrationEngine: FrameRegistrationEngine
    private var referenceFrame: VisionFrame?
    private var registrationReference: RegistrationReferenceFrame?

    public init(
        registrationConfiguration: FrameRegistrationConfiguration = .default,
        changeDetectionConfiguration: ChangeDetectionConfiguration = .default
    ) {
        self.registrationConfiguration = registrationConfiguration
        self.changeDetector = FrameChangeDetector(configuration: changeDetectionConfiguration)
        self.registrationEngine = FrameRegistrationEngine(configuration: registrationConfiguration)
    }

    public mutating func process(_ frame: VisionFrame) async throws -> [VisionPipelineEvent] {
        guard let referenceFrame, let registrationReference else {
            do {
                let registrationReference = try RegistrationReferenceFrame(
                    frame: frame,
                    minimumFeatureCount: registrationConfiguration.minimumFeatureCount
                )
                self.referenceFrame = frame
                self.registrationReference = registrationReference

                return [
                    changeEvent(
                        frame: frame,
                        result: ChangeDetectionResult(
                            status: .noChange,
                            frameSequenceIndex: frame.sequenceIndex,
                            frameTimestamp: frame.timestamp,
                            changedPixelRatio: 0,
                            maximumMagnitude: 0,
                            validComparisonPixelRatio: 1,
                            candidates: [],
                            registrationStatus: .referenceReady
                        )
                    )
                ]
            } catch {
                return [
                    changeEvent(
                        frame: frame,
                        result: ChangeDetectionResult(
                            status: .invalidFrame,
                            frameSequenceIndex: frame.sequenceIndex,
                            frameTimestamp: frame.timestamp,
                            changedPixelRatio: 0,
                            maximumMagnitude: 0,
                            validComparisonPixelRatio: 0,
                            candidates: [],
                            registrationStatus: .invalidFrame
                        )
                    )
                ]
            }
        }

        let registration = try registrationEngine.register(currentFrame: frame, against: registrationReference)
        let changeResult = try changeDetector.detectChanges(
            referenceFrame: referenceFrame,
            currentFrame: frame,
            registration: registration
        )

        return [
            VisionPipelineEvent(
                frameSequenceIndex: frame.sequenceIndex,
                frameTimestamp: frame.timestamp,
                stage: .frameRegistration,
                diagnostics: try FrameRegistrationDiagnostics.diagnostics(for: registration)
            ),
            changeEvent(frame: frame, result: changeResult)
        ]
    }

    private func changeEvent(frame: VisionFrame, result: ChangeDetectionResult) -> VisionPipelineEvent {
        VisionPipelineEvent(
            frameSequenceIndex: frame.sequenceIndex,
            frameTimestamp: frame.timestamp,
            stage: .changeMapGeneration,
            diagnostics: ChangeDetectionDiagnostics.diagnostics(for: result)
        )
    }
}

public enum ChangeDetectionDiagnostics {
    public static func diagnostics(for result: ChangeDetectionResult) -> [VisionFrameDiagnostic] {
        var diagnostics: [VisionFrameDiagnostic] = []
        append("changeStatus", statusCode(result.status), to: &diagnostics)
        append("changeCandidateCount", Double(result.candidates.count), to: &diagnostics)
        append("changedPixelRatio", result.changedPixelRatio, to: &diagnostics)
        append("maximumChangeMagnitude", result.maximumMagnitude, to: &diagnostics)
        append("validComparisonPixelRatio", result.validComparisonPixelRatio, to: &diagnostics)
        append("registrationStatusForChange", FrameRegistrationDiagnostics.statusCodeForDiagnostics(result.registrationStatus), to: &diagnostics)

        if let firstCandidate = result.candidates.first {
            append("firstCandidateCentroidX", firstCandidate.centroid.x, to: &diagnostics)
            append("firstCandidateCentroidY", firstCandidate.centroid.y, to: &diagnostics)
            append("firstCandidateAreaPixels", Double(firstCandidate.areaPixels), to: &diagnostics)
        }

        return diagnostics
    }

    private static func append(_ key: String, _ value: Double, to diagnostics: inout [VisionFrameDiagnostic]) {
        if let diagnostic = try? VisionFrameDiagnostic(key: key, value: value) {
            diagnostics.append(diagnostic)
        }
    }

    private static func statusCode(_ status: ChangeDetectionStatus) -> Double {
        switch status {
        case .noChange: return 1
        case .localizedChangeDetected: return 2
        case .globalChangeRejected: return 3
        case .skippedDueToRegistration: return 4
        case .invalidFrame: return 5
        }
    }
}

public enum FrameChangeDetectionValidationError: Error, Equatable {
    case invalidPixelBuffer
    case invalidLuminanceValue
    case invalidRegion
    case invalidRegionArea
    case invalidCandidateID
    case invalidMetric
    case invalidConfiguration
    case incompatibleDimensions
    case invalidValidityMask
}

public enum TemporalConfidenceBand: String, Codable, Equatable, Sendable {
    case low
    case medium
    case high
}

public enum TemporalCandidateState: String, Codable, Equatable, Sendable {
    case observing
    case persistentCandidate
    case highConfidence
    case mediumConfidence
    case lowConfidence
    case rejectedTransient
    case rejectedUnstable
    case suppressedKnownImpact
}

public enum TemporalSuppressionReason: String, Codable, Equatable, Sendable {
    case knownImpactOverlap
    case insufficientPersistence
    case unstablePosition
}

public struct KnownImpact: Codable, Equatable, Sendable {
    public let id: String
    public let centroid: NormalizedImagePoint
    public let radius: Double
    public let firstConfirmedFrameSequenceIndex: Int
    public let firstConfirmedTimestamp: TimeInterval

    public init(
        id: String,
        centroid: NormalizedImagePoint,
        radius: Double,
        firstConfirmedFrameSequenceIndex: Int,
        firstConfirmedTimestamp: TimeInterval
    ) throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TemporalConfirmationValidationError.invalidIdentifier
        }
        guard radius > 0, radius.isFinite else {
            throw TemporalConfirmationValidationError.invalidConfiguration
        }

        self.id = id
        self.centroid = centroid
        self.radius = radius
        self.firstConfirmedFrameSequenceIndex = firstConfirmedFrameSequenceIndex
        self.firstConfirmedTimestamp = firstConfirmedTimestamp
    }
}

public struct TemporalConfirmationConfiguration: Codable, Equatable, Sendable {
    public let minimumObservedFrames: Int
    public let minimumConsecutiveObservations: Int
    public let maximumAllowedMissingFrames: Int
    public let maximumCentroidDrift: Double
    public let minimumRegionOverlapRatio: Double
    public let knownImpactSuppressionRadius: Double
    public let highConfidenceThreshold: Double
    public let mediumConfidenceThreshold: Double

    public init(
        minimumObservedFrames: Int = 3,
        minimumConsecutiveObservations: Int = 2,
        maximumAllowedMissingFrames: Int = 0,
        maximumCentroidDrift: Double = 0.035,
        minimumRegionOverlapRatio: Double = 0.2,
        knownImpactSuppressionRadius: Double = 0.035,
        highConfidenceThreshold: Double = 0.85,
        mediumConfidenceThreshold: Double = 0.60
    ) throws {
        guard minimumObservedFrames > 0,
              minimumConsecutiveObservations > 0,
              maximumAllowedMissingFrames >= 0 else {
            throw TemporalConfirmationValidationError.invalidConfiguration
        }
        guard maximumCentroidDrift > 0, maximumCentroidDrift.isFinite,
              knownImpactSuppressionRadius > 0, knownImpactSuppressionRadius.isFinite,
              (0...1).contains(minimumRegionOverlapRatio) else {
            throw TemporalConfirmationValidationError.invalidConfiguration
        }
        guard 0 < mediumConfidenceThreshold,
              mediumConfidenceThreshold < highConfidenceThreshold,
              highConfidenceThreshold <= 1 else {
            throw TemporalConfirmationValidationError.invalidConfiguration
        }

        self.minimumObservedFrames = minimumObservedFrames
        self.minimumConsecutiveObservations = minimumConsecutiveObservations
        self.maximumAllowedMissingFrames = maximumAllowedMissingFrames
        self.maximumCentroidDrift = maximumCentroidDrift
        self.minimumRegionOverlapRatio = minimumRegionOverlapRatio
        self.knownImpactSuppressionRadius = knownImpactSuppressionRadius
        self.highConfidenceThreshold = highConfidenceThreshold
        self.mediumConfidenceThreshold = mediumConfidenceThreshold
    }

    public static let `default` = try! TemporalConfirmationConfiguration()
}

public struct TemporalImpactCandidate: Codable, Equatable, Sendable {
    public let id: String
    public let sourceCandidateID: String?
    public let state: TemporalCandidateState
    public let centroid: NormalizedImagePoint
    public let bounds: NormalizedImageRegion
    public let firstObservedFrameSequenceIndex: Int
    public let lastObservedFrameSequenceIndex: Int
    public let firstObservedTimestamp: TimeInterval
    public let lastObservedTimestamp: TimeInterval
    public let observedFrameCount: Int
    public let consecutiveObservationCount: Int
    public let missedFrameCount: Int
    public let maximumCentroidDrift: Double
    public let confidence: Double
    public let confidenceBand: TemporalConfidenceBand
    public let suppressionReason: TemporalSuppressionReason?

    public init(
        id: String,
        sourceCandidateID: String?,
        state: TemporalCandidateState,
        centroid: NormalizedImagePoint,
        bounds: NormalizedImageRegion,
        firstObservedFrameSequenceIndex: Int,
        lastObservedFrameSequenceIndex: Int,
        firstObservedTimestamp: TimeInterval,
        lastObservedTimestamp: TimeInterval,
        observedFrameCount: Int,
        consecutiveObservationCount: Int,
        missedFrameCount: Int,
        maximumCentroidDrift: Double,
        confidence: Double,
        confidenceBand: TemporalConfidenceBand,
        suppressionReason: TemporalSuppressionReason? = nil
    ) throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TemporalConfirmationValidationError.invalidIdentifier
        }
        guard observedFrameCount > 0,
              consecutiveObservationCount >= 0,
              missedFrameCount >= 0,
              maximumCentroidDrift >= 0,
              maximumCentroidDrift.isFinite,
              (0...1).contains(confidence) else {
            throw TemporalConfirmationValidationError.invalidMetric
        }

        self.id = id
        self.sourceCandidateID = sourceCandidateID
        self.state = state
        self.centroid = centroid
        self.bounds = bounds
        self.firstObservedFrameSequenceIndex = firstObservedFrameSequenceIndex
        self.lastObservedFrameSequenceIndex = lastObservedFrameSequenceIndex
        self.firstObservedTimestamp = firstObservedTimestamp
        self.lastObservedTimestamp = lastObservedTimestamp
        self.observedFrameCount = observedFrameCount
        self.consecutiveObservationCount = consecutiveObservationCount
        self.missedFrameCount = missedFrameCount
        self.maximumCentroidDrift = maximumCentroidDrift
        self.confidence = confidence
        self.confidenceBand = confidenceBand
        self.suppressionReason = suppressionReason
    }
}

public struct TemporalConfirmationResult: Codable, Equatable, Sendable {
    public let frameSequenceIndex: Int
    public let frameTimestamp: TimeInterval
    public let rawCandidateCount: Int
    public let emittedCandidates: [TemporalImpactCandidate]
    public let activeTrackCount: Int
    public let knownImpactCount: Int
    public let skippedFrame: Bool

    public var highConfidenceCandidates: [TemporalImpactCandidate] {
        emittedCandidates.filter { $0.confidenceBand == .high && $0.state == .highConfidence }
    }

    public var mediumConfidenceCandidates: [TemporalImpactCandidate] {
        emittedCandidates.filter { $0.confidenceBand == .medium && $0.state != .suppressedKnownImpact }
    }
}

public enum LiveImpactEventSource: String, Codable, Equatable, Sendable {
    case automaticVisualConfirmation
}

public enum LiveMonitoringStatus: String, Codable, Equatable, Sendable {
    case idle
    case monitoring
    case degraded
    case ended
}

public struct LiveImpactEvent: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let shotIndex: Int
    public let frameSequenceIndex: Int
    public let timestamp: TimeInterval
    public let normalizedCoordinate: NormalizedImagePoint
    public let confidence: Double
    public let confidenceBand: TemporalConfidenceBand
    public let temporalCandidateID: String
    public let source: LiveImpactEventSource

    public init(
        id: String,
        shotIndex: Int,
        frameSequenceIndex: Int,
        timestamp: TimeInterval,
        normalizedCoordinate: NormalizedImagePoint,
        confidence: Double,
        confidenceBand: TemporalConfidenceBand,
        temporalCandidateID: String,
        source: LiveImpactEventSource = .automaticVisualConfirmation
    ) throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !temporalCandidateID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              shotIndex > 0,
              frameSequenceIndex >= 0,
              timestamp >= 0,
              timestamp.isFinite,
              (0...1).contains(confidence) else {
            throw LiveImpactEventValidationError.invalidEvent
        }

        self.id = id
        self.shotIndex = shotIndex
        self.frameSequenceIndex = frameSequenceIndex
        self.timestamp = timestamp
        self.normalizedCoordinate = normalizedCoordinate
        self.confidence = confidence
        self.confidenceBand = confidenceBand
        self.temporalCandidateID = temporalCandidateID
        self.source = source
    }
}

public struct LiveImpactCandidateSnapshot: Codable, Equatable, Sendable {
    public let temporalCandidateID: String
    public let frameSequenceIndex: Int
    public let timestamp: TimeInterval
    public let normalizedCoordinate: NormalizedImagePoint
    public let confidence: Double
    public let confidenceBand: TemporalConfidenceBand
}

public struct LiveImpactFrameOutcome: Codable, Equatable, Sendable {
    public let frameSequenceIndex: Int
    public let timestamp: TimeInterval
    public let status: LiveMonitoringStatus
    public let newEvents: [LiveImpactEvent]
    public let mediumConfidenceCandidates: [LiveImpactCandidateSnapshot]
    public let totalEventCount: Int
    public let droppedOutOfOrderResult: Bool
}

public struct LiveImpactSession: Sendable {
    private var status: LiveMonitoringStatus = .idle
    private var events: [LiveImpactEvent] = []
    private var emittedTemporalCandidateIDs = Set<String>()
    private var lastAcceptedFrameSequenceIndex: Int?

    public init() {}

    public var currentStatus: LiveMonitoringStatus {
        status
    }

    public var orderedEvents: [LiveImpactEvent] {
        events
    }

    public mutating func startString() {
        status = .monitoring
        events = []
        emittedTemporalCandidateIDs = []
        lastAcceptedFrameSequenceIndex = nil
    }

    public mutating func endString() {
        status = .ended
    }

    public mutating func process(_ temporalResult: TemporalConfirmationResult) throws -> LiveImpactFrameOutcome {
        guard status == .monitoring else {
            return LiveImpactFrameOutcome(
                frameSequenceIndex: temporalResult.frameSequenceIndex,
                timestamp: temporalResult.frameTimestamp,
                status: status,
                newEvents: [],
                mediumConfidenceCandidates: [],
                totalEventCount: events.count,
                droppedOutOfOrderResult: false
            )
        }

        if let lastAcceptedFrameSequenceIndex,
           temporalResult.frameSequenceIndex <= lastAcceptedFrameSequenceIndex {
            return LiveImpactFrameOutcome(
                frameSequenceIndex: temporalResult.frameSequenceIndex,
                timestamp: temporalResult.frameTimestamp,
                status: status,
                newEvents: [],
                mediumConfidenceCandidates: [],
                totalEventCount: events.count,
                droppedOutOfOrderResult: true
            )
        }

        lastAcceptedFrameSequenceIndex = temporalResult.frameSequenceIndex
        status = temporalResult.skippedFrame ? .degraded : .monitoring
        let highCandidates = temporalResult.highConfidenceCandidates.sorted {
            if $0.lastObservedFrameSequenceIndex == $1.lastObservedFrameSequenceIndex {
                return $0.id < $1.id
            }

            return $0.lastObservedFrameSequenceIndex < $1.lastObservedFrameSequenceIndex
        }

        var newEvents: [LiveImpactEvent] = []
        for candidate in highCandidates where !emittedTemporalCandidateIDs.contains(candidate.id) {
            emittedTemporalCandidateIDs.insert(candidate.id)
            let event = try LiveImpactEvent(
                id: "live-impact-\(events.count + newEvents.count + 1)",
                shotIndex: events.count + newEvents.count + 1,
                frameSequenceIndex: candidate.lastObservedFrameSequenceIndex,
                timestamp: candidate.lastObservedTimestamp,
                normalizedCoordinate: candidate.centroid,
                confidence: candidate.confidence,
                confidenceBand: candidate.confidenceBand,
                temporalCandidateID: candidate.id
            )
            newEvents.append(event)
        }

        events.append(contentsOf: newEvents)
        events.sort {
            if $0.frameSequenceIndex == $1.frameSequenceIndex {
                return $0.shotIndex < $1.shotIndex
            }

            return $0.frameSequenceIndex < $1.frameSequenceIndex
        }

        let mediumCandidates = temporalResult.mediumConfidenceCandidates.map {
            LiveImpactCandidateSnapshot(
                temporalCandidateID: $0.id,
                frameSequenceIndex: $0.lastObservedFrameSequenceIndex,
                timestamp: $0.lastObservedTimestamp,
                normalizedCoordinate: $0.centroid,
                confidence: $0.confidence,
                confidenceBand: $0.confidenceBand
            )
        }

        return LiveImpactFrameOutcome(
            frameSequenceIndex: temporalResult.frameSequenceIndex,
            timestamp: temporalResult.frameTimestamp,
            status: status,
            newEvents: newEvents,
            mediumConfidenceCandidates: mediumCandidates,
            totalEventCount: events.count,
            droppedOutOfOrderResult: false
        )
    }
}

public struct LiveAnalysisConfiguration: Codable, Equatable, Sendable {
    public let minimumFrameInterval: TimeInterval
    public let allowsStaleFrameDropping: Bool
    public let maximumConsecutiveSkippedFramesBeforeDegraded: Int

    public init(
        minimumFrameInterval: TimeInterval = 0.1,
        allowsStaleFrameDropping: Bool = true,
        maximumConsecutiveSkippedFramesBeforeDegraded: Int = 3
    ) throws {
        guard minimumFrameInterval > 0,
              minimumFrameInterval.isFinite,
              maximumConsecutiveSkippedFramesBeforeDegraded >= 0 else {
            throw LiveImpactEventValidationError.invalidConfiguration
        }

        self.minimumFrameInterval = minimumFrameInterval
        self.allowsStaleFrameDropping = allowsStaleFrameDropping
        self.maximumConsecutiveSkippedFramesBeforeDegraded = maximumConsecutiveSkippedFramesBeforeDegraded
    }

    public static let `default` = try! LiveAnalysisConfiguration()
}

public struct LiveAnalysisDiagnostics: Codable, Equatable, Sendable {
    public let capturedFrameCount: Int
    public let analyzedFrameCount: Int
    public let droppedAnalysisFrameCount: Int
    public let inFlightTaskCount: Int
    public let averageProcessingDuration: TimeInterval
    public let registrationFailureCount: Int

    public init(
        capturedFrameCount: Int = 0,
        analyzedFrameCount: Int = 0,
        droppedAnalysisFrameCount: Int = 0,
        inFlightTaskCount: Int = 0,
        averageProcessingDuration: TimeInterval = 0,
        registrationFailureCount: Int = 0
    ) {
        self.capturedFrameCount = capturedFrameCount
        self.analyzedFrameCount = analyzedFrameCount
        self.droppedAnalysisFrameCount = droppedAnalysisFrameCount
        self.inFlightTaskCount = inFlightTaskCount
        self.averageProcessingDuration = averageProcessingDuration
        self.registrationFailureCount = registrationFailureCount
    }
}

public enum LiveImpactEventValidationError: Error, Equatable {
    case invalidEvent
    case invalidConfiguration
}

public struct TemporalImpactConfirmer: Sendable {
    public let configuration: TemporalConfirmationConfiguration
    private var tracks: [TemporalCandidateTrack] = []
    private var knownImpacts: [KnownImpact]
    private var nextTrackNumber = 1

    public init(
        configuration: TemporalConfirmationConfiguration = .default,
        knownImpacts: [KnownImpact] = []
    ) {
        self.configuration = configuration
        self.knownImpacts = knownImpacts
    }

    public var currentKnownImpacts: [KnownImpact] {
        knownImpacts
    }

    public mutating func process(_ changeResult: ChangeDetectionResult) throws -> TemporalConfirmationResult {
        let rawCandidates = changeResult.candidates
        guard changeResult.status == .localizedChangeDetected else {
            let emitted = try ageTracks(
                frameSequenceIndex: changeResult.frameSequenceIndex,
                frameTimestamp: changeResult.frameTimestamp,
                validNoChangeFrame: changeResult.status == .noChange
            )
            return TemporalConfirmationResult(
                frameSequenceIndex: changeResult.frameSequenceIndex,
                frameTimestamp: changeResult.frameTimestamp,
                rawCandidateCount: rawCandidates.count,
                emittedCandidates: emitted,
                activeTrackCount: tracks.count,
                knownImpactCount: knownImpacts.count,
                skippedFrame: changeResult.status != .noChange
            )
        }

        var matchedTrackIDs = Set<String>()
        var emitted: [TemporalImpactCandidate] = []

        for candidate in rawCandidates {
            if let knownImpact = knownImpact(overlapping: candidate) {
                emitted.append(try suppressedCandidate(from: candidate, knownImpact: knownImpact))
                continue
            }

            if let trackIndex = bestTrackIndex(for: candidate, excluding: matchedTrackIDs) {
                tracks[trackIndex].observe(candidate)
                matchedTrackIDs.insert(tracks[trackIndex].id)
                let temporalCandidate = try outputCandidate(for: tracks[trackIndex], sourceCandidateID: candidate.id)
                emitted.append(temporalCandidate)

                if temporalCandidate.state == .highConfidence {
                    knownImpacts.append(try KnownImpact(
                        id: temporalCandidate.id,
                        centroid: temporalCandidate.centroid,
                        radius: configuration.knownImpactSuppressionRadius,
                        firstConfirmedFrameSequenceIndex: temporalCandidate.lastObservedFrameSequenceIndex,
                        firstConfirmedTimestamp: temporalCandidate.lastObservedTimestamp
                    ))
                    tracks[trackIndex].hasEmittedHighConfidence = true
                    tracks[trackIndex].isFinal = true
                }
            } else {
                let track = TemporalCandidateTrack(id: "temporal-\(nextTrackNumber)", firstCandidate: candidate)
                nextTrackNumber += 1
                tracks.append(track)
                matchedTrackIDs.insert(track.id)
                emitted.append(try outputCandidate(for: track, sourceCandidateID: candidate.id))
            }
        }

        emitted.append(contentsOf: try ageUnmatchedTracks(
            matchedTrackIDs: matchedTrackIDs,
            frameSequenceIndex: changeResult.frameSequenceIndex,
            frameTimestamp: changeResult.frameTimestamp
        ))

        tracks.removeAll { $0.isFinal }

        return TemporalConfirmationResult(
            frameSequenceIndex: changeResult.frameSequenceIndex,
            frameTimestamp: changeResult.frameTimestamp,
            rawCandidateCount: rawCandidates.count,
            emittedCandidates: emitted,
            activeTrackCount: tracks.count,
            knownImpactCount: knownImpacts.count,
            skippedFrame: false
        )
    }

    private func bestTrackIndex(for candidate: ChangeCandidate, excluding matchedTrackIDs: Set<String>) -> Int? {
        var best: (index: Int, distance: Double)?

        for index in tracks.indices where !tracks[index].isFinal && !matchedTrackIDs.contains(tracks[index].id) {
            let distance = normalizedDistance(candidate.centroid, tracks[index].centroid)
            let overlap = overlapRatio(candidate.bounds, tracks[index].bounds)
            guard distance <= configuration.maximumCentroidDrift ||
                  overlap >= configuration.minimumRegionOverlapRatio else {
                continue
            }

            if best == nil || distance < best!.distance {
                best = (index, distance)
            }
        }

        return best?.index
    }

    private func knownImpact(overlapping candidate: ChangeCandidate) -> KnownImpact? {
        knownImpacts.first { knownImpact in
            normalizedDistance(candidate.centroid, knownImpact.centroid) <= knownImpact.radius
        }
    }

    private mutating func ageTracks(
        frameSequenceIndex: Int,
        frameTimestamp: TimeInterval,
        validNoChangeFrame: Bool
    ) throws -> [TemporalImpactCandidate] {
        var emitted: [TemporalImpactCandidate] = []

        for index in tracks.indices where !tracks[index].isFinal {
            tracks[index].missedFrameCount += 1
            tracks[index].consecutiveObservationCount = 0

            if validNoChangeFrame && tracks[index].missedFrameCount > configuration.maximumAllowedMissingFrames {
                tracks[index].isFinal = true
                emitted.append(try outputCandidate(
                    for: tracks[index],
                    sourceCandidateID: nil,
                    forcedState: .rejectedTransient,
                    forcedReason: .insufficientPersistence,
                    frameSequenceIndex: frameSequenceIndex,
                    frameTimestamp: frameTimestamp
                ))
            }
        }

        tracks.removeAll { $0.isFinal }
        return emitted
    }

    private mutating func ageUnmatchedTracks(
        matchedTrackIDs: Set<String>,
        frameSequenceIndex: Int,
        frameTimestamp: TimeInterval
    ) throws -> [TemporalImpactCandidate] {
        var emitted: [TemporalImpactCandidate] = []

        for index in tracks.indices where !matchedTrackIDs.contains(tracks[index].id) && !tracks[index].isFinal {
            tracks[index].missedFrameCount += 1
            tracks[index].consecutiveObservationCount = 0

            if tracks[index].missedFrameCount > configuration.maximumAllowedMissingFrames {
                tracks[index].isFinal = true
                emitted.append(try outputCandidate(
                    for: tracks[index],
                    sourceCandidateID: nil,
                    forcedState: .rejectedTransient,
                    forcedReason: .insufficientPersistence,
                    frameSequenceIndex: frameSequenceIndex,
                    frameTimestamp: frameTimestamp
                ))
            }
        }

        return emitted
    }

    private func outputCandidate(
        for track: TemporalCandidateTrack,
        sourceCandidateID: String?,
        forcedState: TemporalCandidateState? = nil,
        forcedReason: TemporalSuppressionReason? = nil,
        frameSequenceIndex: Int? = nil,
        frameTimestamp: TimeInterval? = nil
    ) throws -> TemporalImpactCandidate {
        let confidence = forcedState == nil ? confidence(for: track) : min(confidence(for: track), 0.59)
        let band = confidenceBand(for: confidence)
        let state = forcedState ?? state(for: track, confidence: confidence, band: band)

        return try TemporalImpactCandidate(
            id: track.id,
            sourceCandidateID: sourceCandidateID,
            state: state,
            centroid: track.centroid,
            bounds: track.bounds,
            firstObservedFrameSequenceIndex: track.firstObservedFrameSequenceIndex,
            lastObservedFrameSequenceIndex: frameSequenceIndex ?? track.lastObservedFrameSequenceIndex,
            firstObservedTimestamp: track.firstObservedTimestamp,
            lastObservedTimestamp: frameTimestamp ?? track.lastObservedTimestamp,
            observedFrameCount: track.observedFrameCount,
            consecutiveObservationCount: track.consecutiveObservationCount,
            missedFrameCount: track.missedFrameCount,
            maximumCentroidDrift: track.maximumCentroidDrift,
            confidence: confidence,
            confidenceBand: band,
            suppressionReason: forcedReason
        )
    }

    private func suppressedCandidate(from candidate: ChangeCandidate, knownImpact: KnownImpact) throws -> TemporalImpactCandidate {
        try TemporalImpactCandidate(
            id: "suppressed-\(candidate.id)",
            sourceCandidateID: candidate.id,
            state: .suppressedKnownImpact,
            centroid: candidate.centroid,
            bounds: candidate.bounds,
            firstObservedFrameSequenceIndex: candidate.frameSequenceIndex,
            lastObservedFrameSequenceIndex: candidate.frameSequenceIndex,
            firstObservedTimestamp: candidate.frameTimestamp,
            lastObservedTimestamp: candidate.frameTimestamp,
            observedFrameCount: 1,
            consecutiveObservationCount: 1,
            missedFrameCount: 0,
            maximumCentroidDrift: normalizedDistance(candidate.centroid, knownImpact.centroid),
            confidence: 0,
            confidenceBand: .low,
            suppressionReason: .knownImpactOverlap
        )
    }

    private func state(
        for track: TemporalCandidateTrack,
        confidence: Double,
        band: TemporalConfidenceBand
    ) -> TemporalCandidateState {
        guard track.observedFrameCount >= configuration.minimumObservedFrames,
              track.consecutiveObservationCount >= configuration.minimumConsecutiveObservations else {
            return band == .medium ? .mediumConfidence : .lowConfidence
        }

        guard track.maximumCentroidDrift <= configuration.maximumCentroidDrift else {
            return .rejectedUnstable
        }

        switch band {
        case .high:
            return track.hasEmittedHighConfidence ? .persistentCandidate : .highConfidence
        case .medium:
            return .mediumConfidence
        case .low:
            return .lowConfidence
        }
    }

    private func confidence(for track: TemporalCandidateTrack) -> Double {
        let persistence = min(1, Double(track.observedFrameCount) / Double(configuration.minimumObservedFrames))
        let stability = max(0, 1 - track.maximumCentroidDrift / configuration.maximumCentroidDrift)
        let visualMagnitude = min(1, track.averageMagnitude / 0.6)
        let visualContrast = min(1, track.averageContrast / 0.6)
        let visualQuality = (visualMagnitude + visualContrast) / 2
        let registrationQuality = min(1, max(0, track.averageRegistrationConfidence))
        var confidence = 0.35 * persistence + 0.25 * stability + 0.25 * visualQuality + 0.15 * registrationQuality

        if track.observedFrameCount == 1 {
            confidence = min(confidence, 0.59)
        } else if track.observedFrameCount < configuration.minimumObservedFrames {
            confidence = min(confidence, configuration.highConfidenceThreshold - 0.01)
        }

        return min(1, max(0, confidence))
    }

    private func confidenceBand(for confidence: Double) -> TemporalConfidenceBand {
        if confidence >= configuration.highConfidenceThreshold {
            return .high
        }

        if confidence >= configuration.mediumConfidenceThreshold {
            return .medium
        }

        return .low
    }
}

private struct TemporalCandidateTrack: Sendable {
    let id: String
    var centroid: NormalizedImagePoint
    var bounds: NormalizedImageRegion
    let firstObservedFrameSequenceIndex: Int
    var lastObservedFrameSequenceIndex: Int
    let firstObservedTimestamp: TimeInterval
    var lastObservedTimestamp: TimeInterval
    var observedFrameCount: Int
    var consecutiveObservationCount: Int
    var missedFrameCount: Int
    var maximumCentroidDrift: Double
    var magnitudeSum: Double
    var contrastSum: Double
    var registrationConfidenceSum: Double
    var hasEmittedHighConfidence = false
    var isFinal = false

    init(id: String, firstCandidate: ChangeCandidate) {
        self.id = id
        self.centroid = firstCandidate.centroid
        self.bounds = firstCandidate.bounds
        self.firstObservedFrameSequenceIndex = firstCandidate.frameSequenceIndex
        self.lastObservedFrameSequenceIndex = firstCandidate.frameSequenceIndex
        self.firstObservedTimestamp = firstCandidate.frameTimestamp
        self.lastObservedTimestamp = firstCandidate.frameTimestamp
        self.observedFrameCount = 1
        self.consecutiveObservationCount = 1
        self.missedFrameCount = 0
        self.maximumCentroidDrift = 0
        self.magnitudeSum = firstCandidate.magnitude
        self.contrastSum = firstCandidate.contrast
        self.registrationConfidenceSum = firstCandidate.registrationConfidence
    }

    mutating func observe(_ candidate: ChangeCandidate) {
        maximumCentroidDrift = max(maximumCentroidDrift, normalizedDistance(candidate.centroid, centroid))
        let nextCount = Double(observedFrameCount + 1)
        if let averagedCentroid = try? NormalizedImagePoint(
            x: (centroid.x * Double(observedFrameCount) + candidate.centroid.x) / nextCount,
            y: (centroid.y * Double(observedFrameCount) + candidate.centroid.y) / nextCount
        ) {
            centroid = averagedCentroid
        }
        bounds = candidate.bounds
        lastObservedFrameSequenceIndex = candidate.frameSequenceIndex
        lastObservedTimestamp = candidate.frameTimestamp
        observedFrameCount += 1
        consecutiveObservationCount += 1
        missedFrameCount = 0
        magnitudeSum += candidate.magnitude
        contrastSum += candidate.contrast
        registrationConfidenceSum += candidate.registrationConfidence
    }

    var averageMagnitude: Double {
        magnitudeSum / Double(observedFrameCount)
    }

    var averageContrast: Double {
        contrastSum / Double(observedFrameCount)
    }

    var averageRegistrationConfidence: Double {
        registrationConfidenceSum / Double(observedFrameCount)
    }
}

public struct TemporalConfirmationProcessor: VisionFrameProcessor {
    private let registrationConfiguration: FrameRegistrationConfiguration
    private let changeDetector: FrameChangeDetector
    private let registrationEngine: FrameRegistrationEngine
    private var temporalConfirmer: TemporalImpactConfirmer
    private var referenceFrame: VisionFrame?
    private var registrationReference: RegistrationReferenceFrame?

    public init(
        registrationConfiguration: FrameRegistrationConfiguration = .default,
        changeDetectionConfiguration: ChangeDetectionConfiguration = .default,
        temporalConfirmationConfiguration: TemporalConfirmationConfiguration = .default,
        knownImpacts: [KnownImpact] = []
    ) {
        self.registrationConfiguration = registrationConfiguration
        self.changeDetector = FrameChangeDetector(configuration: changeDetectionConfiguration)
        self.registrationEngine = FrameRegistrationEngine(configuration: registrationConfiguration)
        self.temporalConfirmer = TemporalImpactConfirmer(
            configuration: temporalConfirmationConfiguration,
            knownImpacts: knownImpacts
        )
    }

    public mutating func process(_ frame: VisionFrame) async throws -> [VisionPipelineEvent] {
        guard let referenceFrame, let registrationReference else {
            do {
                let registrationReference = try RegistrationReferenceFrame(
                    frame: frame,
                    minimumFeatureCount: registrationConfiguration.minimumFeatureCount
                )
                self.referenceFrame = frame
                self.registrationReference = registrationReference
                let changeResult = ChangeDetectionResult(
                    status: .noChange,
                    frameSequenceIndex: frame.sequenceIndex,
                    frameTimestamp: frame.timestamp,
                    changedPixelRatio: 0,
                    maximumMagnitude: 0,
                    validComparisonPixelRatio: 1,
                    candidates: [],
                    registrationStatus: .referenceReady
                )
                let temporalResult = try temporalConfirmer.process(changeResult)

                return [
                    changeEvent(frame: frame, result: changeResult),
                    temporalEvent(frame: frame, result: temporalResult)
                ]
            } catch {
                let changeResult = ChangeDetectionResult(
                    status: .invalidFrame,
                    frameSequenceIndex: frame.sequenceIndex,
                    frameTimestamp: frame.timestamp,
                    changedPixelRatio: 0,
                    maximumMagnitude: 0,
                    validComparisonPixelRatio: 0,
                    candidates: [],
                    registrationStatus: .invalidFrame
                )
                let temporalResult = try temporalConfirmer.process(changeResult)

                return [
                    changeEvent(frame: frame, result: changeResult),
                    temporalEvent(frame: frame, result: temporalResult)
                ]
            }
        }

        let registration = try registrationEngine.register(currentFrame: frame, against: registrationReference)
        let changeResult = try changeDetector.detectChanges(
            referenceFrame: referenceFrame,
            currentFrame: frame,
            registration: registration
        )
        let temporalResult = try temporalConfirmer.process(changeResult)

        return [
            VisionPipelineEvent(
                frameSequenceIndex: frame.sequenceIndex,
                frameTimestamp: frame.timestamp,
                stage: .frameRegistration,
                diagnostics: try FrameRegistrationDiagnostics.diagnostics(for: registration)
            ),
            changeEvent(frame: frame, result: changeResult),
            temporalEvent(frame: frame, result: temporalResult)
        ]
    }

    private func changeEvent(frame: VisionFrame, result: ChangeDetectionResult) -> VisionPipelineEvent {
        VisionPipelineEvent(
            frameSequenceIndex: frame.sequenceIndex,
            frameTimestamp: frame.timestamp,
            stage: .changeMapGeneration,
            diagnostics: ChangeDetectionDiagnostics.diagnostics(for: result)
        )
    }

    private func temporalEvent(frame: VisionFrame, result: TemporalConfirmationResult) -> VisionPipelineEvent {
        VisionPipelineEvent(
            frameSequenceIndex: frame.sequenceIndex,
            frameTimestamp: frame.timestamp,
            stage: .temporalConfirmation,
            diagnostics: TemporalConfirmationDiagnostics.diagnostics(for: result)
        )
    }
}

public enum TemporalConfirmationDiagnostics {
    public static func diagnostics(for result: TemporalConfirmationResult) -> [VisionFrameDiagnostic] {
        var diagnostics: [VisionFrameDiagnostic] = []
        append("temporalRawCandidateCount", Double(result.rawCandidateCount), to: &diagnostics)
        append("temporalEmittedCandidateCount", Double(result.emittedCandidates.count), to: &diagnostics)
        append("temporalActiveTrackCount", Double(result.activeTrackCount), to: &diagnostics)
        append("temporalKnownImpactCount", Double(result.knownImpactCount), to: &diagnostics)
        append("temporalSkippedFrame", result.skippedFrame ? 1 : 0, to: &diagnostics)
        append("temporalHighConfidenceCount", Double(result.emittedCandidates.filter { $0.state == .highConfidence }.count), to: &diagnostics)
        append("temporalMediumConfidenceCount", Double(result.emittedCandidates.filter { $0.confidenceBand == .medium }.count), to: &diagnostics)
        append("temporalLowConfidenceCount", Double(result.emittedCandidates.filter { $0.confidenceBand == .low }.count), to: &diagnostics)
        append("temporalSuppressedKnownImpactCount", Double(result.emittedCandidates.filter { $0.state == .suppressedKnownImpact }.count), to: &diagnostics)
        append("temporalRejectedTransientCount", Double(result.emittedCandidates.filter { $0.state == .rejectedTransient }.count), to: &diagnostics)

        if let first = result.emittedCandidates.first {
            append("temporalFirstConfidence", first.confidence, to: &diagnostics)
            append("temporalFirstConfidenceBand", bandCode(first.confidenceBand), to: &diagnostics)
            append("temporalFirstState", stateCode(first.state), to: &diagnostics)
            append("temporalFirstCentroidX", first.centroid.x, to: &diagnostics)
            append("temporalFirstCentroidY", first.centroid.y, to: &diagnostics)
            append("temporalFirstObservedFrames", Double(first.observedFrameCount), to: &diagnostics)
        }

        return diagnostics
    }

    private static func append(_ key: String, _ value: Double, to diagnostics: inout [VisionFrameDiagnostic]) {
        if let diagnostic = try? VisionFrameDiagnostic(key: key, value: value) {
            diagnostics.append(diagnostic)
        }
    }

    private static func bandCode(_ band: TemporalConfidenceBand) -> Double {
        switch band {
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        }
    }

    private static func stateCode(_ state: TemporalCandidateState) -> Double {
        switch state {
        case .observing: return 1
        case .persistentCandidate: return 2
        case .highConfidence: return 3
        case .mediumConfidence: return 4
        case .lowConfidence: return 5
        case .rejectedTransient: return 6
        case .rejectedUnstable: return 7
        case .suppressedKnownImpact: return 8
        }
    }
}

public enum LiveImpactDiagnostics {
    public static func diagnostics(for outcome: LiveImpactFrameOutcome) -> [VisionFrameDiagnostic] {
        var diagnostics: [VisionFrameDiagnostic] = []
        append("liveImpactNewEventCount", Double(outcome.newEvents.count), to: &diagnostics)
        append("liveImpactTotalEventCount", Double(outcome.totalEventCount), to: &diagnostics)
        append("liveImpactMediumCandidateCount", Double(outcome.mediumConfidenceCandidates.count), to: &diagnostics)
        append("liveImpactStatus", statusCode(outcome.status), to: &diagnostics)
        append("liveImpactDroppedOutOfOrderResult", outcome.droppedOutOfOrderResult ? 1 : 0, to: &diagnostics)

        if let first = outcome.newEvents.first {
            append("liveImpactFirstShotIndex", Double(first.shotIndex), to: &diagnostics)
            append("liveImpactFirstCoordinateX", first.normalizedCoordinate.x, to: &diagnostics)
            append("liveImpactFirstCoordinateY", first.normalizedCoordinate.y, to: &diagnostics)
            append("liveImpactFirstConfidence", first.confidence, to: &diagnostics)
        }

        return diagnostics
    }

    public static func diagnostics(for metrics: LiveAnalysisDiagnostics) -> [VisionFrameDiagnostic] {
        var diagnostics: [VisionFrameDiagnostic] = []
        append("liveCapturedFrameCount", Double(metrics.capturedFrameCount), to: &diagnostics)
        append("liveAnalyzedFrameCount", Double(metrics.analyzedFrameCount), to: &diagnostics)
        append("liveDroppedAnalysisFrameCount", Double(metrics.droppedAnalysisFrameCount), to: &diagnostics)
        append("liveInFlightTaskCount", Double(metrics.inFlightTaskCount), to: &diagnostics)
        append("liveAverageProcessingDuration", metrics.averageProcessingDuration, to: &diagnostics)
        append("liveRegistrationFailureCount", Double(metrics.registrationFailureCount), to: &diagnostics)
        return diagnostics
    }

    private static func append(_ key: String, _ value: Double, to diagnostics: inout [VisionFrameDiagnostic]) {
        if let diagnostic = try? VisionFrameDiagnostic(key: key, value: value) {
            diagnostics.append(diagnostic)
        }
    }

    private static func statusCode(_ status: LiveMonitoringStatus) -> Double {
        switch status {
        case .idle: return 1
        case .monitoring: return 2
        case .degraded: return 3
        case .ended: return 4
        }
    }
}

public enum TemporalConfirmationValidationError: Error, Equatable {
    case invalidConfiguration
    case invalidIdentifier
    case invalidMetric
}

private func normalizedDistance(_ lhs: NormalizedImagePoint, _ rhs: NormalizedImagePoint) -> Double {
    hypot(lhs.x - rhs.x, lhs.y - rhs.y)
}

private func overlapRatio(_ lhs: NormalizedImageRegion, _ rhs: NormalizedImageRegion) -> Double {
    let minX = max(lhs.minX, rhs.minX)
    let minY = max(lhs.minY, rhs.minY)
    let maxX = min(lhs.maxX, rhs.maxX)
    let maxY = min(lhs.maxY, rhs.maxY)
    guard maxX > minX, maxY > minY else {
        return 0
    }

    let intersection = (maxX - minX) * (maxY - minY)
    let smallerArea = min(lhs.width * lhs.height, rhs.width * rhs.height)
    guard smallerArea > 0 else {
        return 0
    }

    return intersection / smallerArea
}
