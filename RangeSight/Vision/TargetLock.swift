import Foundation

public struct NormalizedImagePoint: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) throws {
        guard (0...1).contains(x), (0...1).contains(y) else {
            throw TargetLockValidationError.pointOutOfBounds
        }

        self.x = x
        self.y = y
    }
}

public struct TargetQuadrilateral: Codable, Equatable, Sendable {
    public let topLeft: NormalizedImagePoint
    public let topRight: NormalizedImagePoint
    public let bottomRight: NormalizedImagePoint
    public let bottomLeft: NormalizedImagePoint

    public init(
        topLeft: NormalizedImagePoint,
        topRight: NormalizedImagePoint,
        bottomRight: NormalizedImagePoint,
        bottomLeft: NormalizedImagePoint
    ) throws {
        let corners = [topLeft, topRight, bottomRight, bottomLeft]
        let area = Self.area(for: corners)

        guard area > 0 else {
            throw TargetLockValidationError.invalidQuadrilateral
        }

        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    public var corners: [NormalizedImagePoint] {
        [topLeft, topRight, bottomRight, bottomLeft]
    }

    public var normalizedArea: Double {
        Self.area(for: corners)
    }

    public var center: NormalizedImagePoint {
        let x = corners.reduce(0) { $0 + $1.x } / Double(corners.count)
        let y = corners.reduce(0) { $0 + $1.y } / Double(corners.count)
        return try! NormalizedImagePoint(x: x, y: y)
    }

    private static func area(for corners: [NormalizedImagePoint]) -> Double {
        guard corners.count >= 3 else { return 0 }

        let sum = corners.enumerated().reduce(0.0) { partial, item in
            let next = corners[(item.offset + 1) % corners.count]
            return partial + item.element.x * next.y - next.x * item.element.y
        }

        return abs(sum) / 2
    }
}

public enum TargetLockSource: String, Codable, Equatable, Sendable {
    case manual
    case assisted
}

public struct ImageQualityMetrics: Codable, Equatable, Sendable {
    public let sharpness: Double
    public let brightness: Double
    public let clippedHighlightRatio: Double
    public let clippedShadowRatio: Double
    public let registrationFeatureCount: Int

    public init(
        sharpness: Double,
        brightness: Double,
        clippedHighlightRatio: Double,
        clippedShadowRatio: Double,
        registrationFeatureCount: Int
    ) throws {
        guard sharpness >= 0 else { throw TargetLockValidationError.negativeMetric("sharpness") }
        guard (0...1).contains(brightness) else { throw TargetLockValidationError.metricOutOfBounds("brightness") }
        guard (0...1).contains(clippedHighlightRatio) else { throw TargetLockValidationError.metricOutOfBounds("clippedHighlightRatio") }
        guard (0...1).contains(clippedShadowRatio) else { throw TargetLockValidationError.metricOutOfBounds("clippedShadowRatio") }
        guard registrationFeatureCount >= 0 else { throw TargetLockValidationError.negativeMetric("registrationFeatureCount") }

        self.sharpness = sharpness
        self.brightness = brightness
        self.clippedHighlightRatio = clippedHighlightRatio
        self.clippedShadowRatio = clippedShadowRatio
        self.registrationFeatureCount = registrationFeatureCount
    }
}

public struct TargetLockQualityThresholds: Codable, Equatable, Sendable {
    public let minimumTargetArea: Double
    public let minimumSharpness: Double
    public let minimumBrightness: Double
    public let maximumBrightness: Double
    public let maximumClippedRatio: Double
    public let minimumRegistrationFeatureCount: Int

    public init(
        minimumTargetArea: Double = 0.12,
        minimumSharpness: Double = 0.55,
        minimumBrightness: Double = 0.18,
        maximumBrightness: Double = 0.86,
        maximumClippedRatio: Double = 0.08,
        minimumRegistrationFeatureCount: Int = 24
    ) throws {
        guard (0...1).contains(minimumTargetArea), minimumTargetArea > 0 else {
            throw TargetLockValidationError.metricOutOfBounds("minimumTargetArea")
        }
        guard minimumSharpness >= 0 else {
            throw TargetLockValidationError.negativeMetric("minimumSharpness")
        }
        guard (0...1).contains(minimumBrightness), (0...1).contains(maximumBrightness), minimumBrightness < maximumBrightness else {
            throw TargetLockValidationError.metricOutOfBounds("brightnessRange")
        }
        guard (0...1).contains(maximumClippedRatio) else {
            throw TargetLockValidationError.metricOutOfBounds("maximumClippedRatio")
        }
        guard minimumRegistrationFeatureCount >= 0 else {
            throw TargetLockValidationError.negativeMetric("minimumRegistrationFeatureCount")
        }

        self.minimumTargetArea = minimumTargetArea
        self.minimumSharpness = minimumSharpness
        self.minimumBrightness = minimumBrightness
        self.maximumBrightness = maximumBrightness
        self.maximumClippedRatio = maximumClippedRatio
        self.minimumRegistrationFeatureCount = minimumRegistrationFeatureCount
    }

    public static let `default` = try! TargetLockQualityThresholds()
}

public enum TargetLockQualityIssue: String, Codable, CaseIterable, Equatable, Sendable {
    case targetTooSmall
    case blurred
    case underExposed
    case overExposed
    case clippedHighlights
    case clippedShadows
    case insufficientRegistrationFeatures
}

public struct PerspectiveNormalizationMetadata: Codable, Equatable, Sendable {
    public let sourceQuadrilateral: TargetQuadrilateral
    public let normalizedPlaneSize: PhysicalDimensions?
    public let transformVersion: Int

    public init(
        sourceQuadrilateral: TargetQuadrilateral,
        normalizedPlaneSize: PhysicalDimensions?,
        transformVersion: Int = 1
    ) throws {
        guard transformVersion > 0 else {
            throw TargetLockValidationError.nonPositiveTransformVersion
        }

        self.sourceQuadrilateral = sourceQuadrilateral
        self.normalizedPlaneSize = normalizedPlaneSize
        self.transformVersion = transformVersion
    }
}

public struct TargetLockAssessment: Codable, Equatable, Sendable {
    public let source: TargetLockSource
    public let quadrilateral: TargetQuadrilateral
    public let qualityMetrics: ImageQualityMetrics
    public let qualityIssues: [TargetLockQualityIssue]
    public let perspective: PerspectiveNormalizationMetadata

    public var canLock: Bool {
        qualityIssues.isEmpty
    }
}

public enum TargetLockEvaluator {
    public static func assess(
        source: TargetLockSource,
        quadrilateral: TargetQuadrilateral,
        qualityMetrics: ImageQualityMetrics,
        targetDimensions: PhysicalDimensions?,
        thresholds: TargetLockQualityThresholds = .default
    ) throws -> TargetLockAssessment {
        var issues: [TargetLockQualityIssue] = []

        if quadrilateral.normalizedArea < thresholds.minimumTargetArea {
            issues.append(.targetTooSmall)
        }

        if qualityMetrics.sharpness < thresholds.minimumSharpness {
            issues.append(.blurred)
        }

        if qualityMetrics.brightness < thresholds.minimumBrightness {
            issues.append(.underExposed)
        }

        if qualityMetrics.brightness > thresholds.maximumBrightness {
            issues.append(.overExposed)
        }

        if qualityMetrics.clippedHighlightRatio > thresholds.maximumClippedRatio {
            issues.append(.clippedHighlights)
        }

        if qualityMetrics.clippedShadowRatio > thresholds.maximumClippedRatio {
            issues.append(.clippedShadows)
        }

        if qualityMetrics.registrationFeatureCount < thresholds.minimumRegistrationFeatureCount {
            issues.append(.insufficientRegistrationFeatures)
        }

        return TargetLockAssessment(
            source: source,
            quadrilateral: quadrilateral,
            qualityMetrics: qualityMetrics,
            qualityIssues: issues,
            perspective: try PerspectiveNormalizationMetadata(
                sourceQuadrilateral: quadrilateral,
                normalizedPlaneSize: targetDimensions
            )
        )
    }
}

public enum TargetLockValidationError: Error, Equatable {
    case pointOutOfBounds
    case invalidQuadrilateral
    case metricOutOfBounds(String)
    case negativeMetric(String)
    case nonPositiveTransformVersion
}
