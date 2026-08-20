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

    public init(
        pixelDifferenceThreshold: Double = 0.18,
        minimumRegionAreaPixels: Int = 2,
        maximumRegionAreaRatio: Double = 0.2,
        globalChangePixelRatio: Double = 0.45
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

        self.pixelDifferenceThreshold = pixelDifferenceThreshold
        self.minimumRegionAreaPixels = minimumRegionAreaPixels
        self.maximumRegionAreaRatio = maximumRegionAreaRatio
        self.globalChangePixelRatio = globalChangePixelRatio
    }

    public static let `default` = try! ChangeDetectionConfiguration()
}

public struct ChangeDetectionResult: Codable, Equatable, Sendable {
    public let status: ChangeDetectionStatus
    public let frameSequenceIndex: Int
    public let frameTimestamp: TimeInterval
    public let changedPixelRatio: Double
    public let maximumMagnitude: Double
    public let candidates: [ChangeCandidate]
    public let registrationStatus: FrameRegistrationStatus

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
                candidates: [],
                registrationStatus: registration.status
            )
        }

        let totalPixels = reference.width * reference.height
        var changed = Array(repeating: false, count: totalPixels)
        var changedCount = 0
        var maximumMagnitude = 0.0

        for index in 0..<totalPixels {
            let magnitude = abs(current.pixels[index] - reference.pixels[index])
            maximumMagnitude = max(maximumMagnitude, magnitude)

            if magnitude >= configuration.pixelDifferenceThreshold {
                changed[index] = true
                changedCount += 1
            }
        }

        let changedRatio = Double(changedCount) / Double(totalPixels)
        guard changedRatio < configuration.globalChangePixelRatio else {
            return ChangeDetectionResult(
                status: .globalChangeRejected,
                frameSequenceIndex: currentFrame.sequenceIndex,
                frameTimestamp: currentFrame.timestamp,
                changedPixelRatio: changedRatio,
                maximumMagnitude: maximumMagnitude,
                candidates: [],
                registrationStatus: registration.status
            )
        }

        let candidates = try connectedComponents(
            changed: changed,
            reference: reference,
            current: current,
            frame: currentFrame,
            registration: registration
        )

        return ChangeDetectionResult(
            status: candidates.isEmpty ? .noChange : .localizedChangeDetected,
            frameSequenceIndex: currentFrame.sequenceIndex,
            frameTimestamp: currentFrame.timestamp,
            changedPixelRatio: changedRatio,
            maximumMagnitude: maximumMagnitude,
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
}
