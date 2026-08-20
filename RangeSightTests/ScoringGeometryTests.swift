import XCTest
@testable import RangeSightCore

final class ScoringGeometryTests: XCTestCase {
    func testNormalizedCoordinatesConvertToCenterOriginPhysicalCoordinates() throws {
        let dimensions = try PhysicalDimensions(width: 10, height: 8, unit: .inch)

        XCTAssertEqual(
            TargetCoordinateConverter.physicalPoint(
                from: try NormalizedTargetCoordinate(x: 0.5, y: 0.5),
                dimensions: dimensions
            ),
            PhysicalPoint(x: 0, y: 0, unit: .inch)
        )

        XCTAssertEqual(
            TargetCoordinateConverter.physicalPoint(
                from: try NormalizedTargetCoordinate(x: 1, y: 0),
                dimensions: dimensions
            ),
            PhysicalPoint(x: 5, y: 4, unit: .inch)
        )
    }

    func testGroupMetricsUsePhysicalCoordinates() throws {
        let points = [
            PhysicalPoint(x: -1, y: 0, unit: .inch),
            PhysicalPoint(x: 1, y: 0, unit: .inch),
            PhysicalPoint(x: 0, y: 2, unit: .inch)
        ]

        let metrics = try GroupMetricCalculator.metrics(
            for: points,
            aimPoint: PhysicalPoint(x: 0, y: 0, unit: .inch)
        )

        XCTAssertEqual(metrics.shotCount, 3)
        XCTAssertEqual(metrics.groupCenter.x, 0, accuracy: 0.0001)
        XCTAssertEqual(metrics.groupCenter.y, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(metrics.extremeSpread, (5.0).squareRoot(), accuracy: 0.0001)
        XCTAssertEqual(metrics.meanRadius, 1.2457, accuracy: 0.0001)
        XCTAssertEqual(metrics.pointOfImpactOffset.y, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(metrics.horizontalStandardDeviation, (2.0 / 3.0).squareRoot(), accuracy: 0.0001)
        XCTAssertEqual(metrics.verticalStandardDeviation, (8.0 / 9.0).squareRoot(), accuracy: 0.0001)
    }

    func testGroupMetricsRejectMixedUnitsAndEmptyGroups() {
        XCTAssertThrowsError(
            try GroupMetricCalculator.metrics(
                for: [],
                aimPoint: PhysicalPoint(x: 0, y: 0, unit: .inch)
            )
        )

        XCTAssertThrowsError(
            try GroupMetricCalculator.metrics(
                for: [
                    PhysicalPoint(x: 0, y: 0, unit: .inch),
                    PhysicalPoint(x: 0, y: 0, unit: .millimeter)
                ],
                aimPoint: PhysicalPoint(x: 0, y: 0, unit: .inch)
            )
        )
    }
}
