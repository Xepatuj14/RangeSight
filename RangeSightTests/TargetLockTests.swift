import XCTest
@testable import RangeSightCore

final class TargetLockTests: XCTestCase {
    func testGoodManualTargetLockProducesPerspectiveMetadata() throws {
        let quadrilateral = try sampleQuadrilateral()
        let dimensions = try PhysicalDimensions(width: 18, height: 30, unit: .inch)

        let assessment = try TargetLockEvaluator.assess(
            source: .manual,
            quadrilateral: quadrilateral,
            qualityMetrics: try ImageQualityMetrics(
                sharpness: 0.82,
                brightness: 0.48,
                clippedHighlightRatio: 0.01,
                clippedShadowRatio: 0.02,
                registrationFeatureCount: 42
            ),
            targetDimensions: dimensions
        )

        XCTAssertTrue(assessment.canLock)
        XCTAssertEqual(assessment.source, .manual)
        XCTAssertEqual(assessment.qualityIssues, [])
        XCTAssertEqual(assessment.perspective.sourceQuadrilateral, quadrilateral)
        XCTAssertEqual(assessment.perspective.normalizedPlaneSize, dimensions)
        XCTAssertEqual(assessment.perspective.transformVersion, 1)
    }

    func testQualityChecksReportEveryBlockingIssueDeterministically() throws {
        let assessment = try TargetLockEvaluator.assess(
            source: .assisted,
            quadrilateral: try TargetQuadrilateral(
                topLeft: try NormalizedImagePoint(x: 0.45, y: 0.45),
                topRight: try NormalizedImagePoint(x: 0.55, y: 0.45),
                bottomRight: try NormalizedImagePoint(x: 0.55, y: 0.55),
                bottomLeft: try NormalizedImagePoint(x: 0.45, y: 0.55)
            ),
            qualityMetrics: try ImageQualityMetrics(
                sharpness: 0.2,
                brightness: 0.1,
                clippedHighlightRatio: 0.12,
                clippedShadowRatio: 0.11,
                registrationFeatureCount: 6
            ),
            targetDimensions: nil
        )

        XCTAssertFalse(assessment.canLock)
        XCTAssertEqual(
            assessment.qualityIssues,
            [
                .targetTooSmall,
                .blurred,
                .underExposed,
                .clippedHighlights,
                .clippedShadows,
                .insufficientRegistrationFeatures
            ]
        )
    }

    func testOverExposedTargetIsDistinctFromUnderExposedTarget() throws {
        let assessment = try TargetLockEvaluator.assess(
            source: .assisted,
            quadrilateral: try sampleQuadrilateral(),
            qualityMetrics: try ImageQualityMetrics(
                sharpness: 0.75,
                brightness: 0.93,
                clippedHighlightRatio: 0.01,
                clippedShadowRatio: 0,
                registrationFeatureCount: 30
            ),
            targetDimensions: nil
        )

        XCTAssertEqual(assessment.qualityIssues, [.overExposed])
    }

    func testRejectsInvalidQuadrilateralAndMetrics() throws {
        XCTAssertThrowsError(
            try NormalizedImagePoint(x: 1.1, y: 0.5)
        ) { error in
            XCTAssertEqual(error as? TargetLockValidationError, .pointOutOfBounds)
        }

        XCTAssertThrowsError(
            try TargetQuadrilateral(
                topLeft: try NormalizedImagePoint(x: 0.5, y: 0.5),
                topRight: try NormalizedImagePoint(x: 0.5, y: 0.5),
                bottomRight: try NormalizedImagePoint(x: 0.5, y: 0.5),
                bottomLeft: try NormalizedImagePoint(x: 0.5, y: 0.5)
            )
        ) { error in
            XCTAssertEqual(error as? TargetLockValidationError, .invalidQuadrilateral)
        }

        XCTAssertThrowsError(
            try ImageQualityMetrics(
                sharpness: 0.8,
                brightness: 1.2,
                clippedHighlightRatio: 0,
                clippedShadowRatio: 0,
                registrationFeatureCount: 30
            )
        ) { error in
            XCTAssertEqual(error as? TargetLockValidationError, .metricOutOfBounds("brightness"))
        }
    }

    private func sampleQuadrilateral() throws -> TargetQuadrilateral {
        try TargetQuadrilateral(
            topLeft: try NormalizedImagePoint(x: 0.18, y: 0.16),
            topRight: try NormalizedImagePoint(x: 0.82, y: 0.18),
            bottomRight: try NormalizedImagePoint(x: 0.78, y: 0.88),
            bottomLeft: try NormalizedImagePoint(x: 0.2, y: 0.86)
        )
    }
}
