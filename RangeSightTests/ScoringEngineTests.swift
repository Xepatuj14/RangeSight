import XCTest
@testable import RangeSightCore

final class ScoringEngineTests: XCTestCase {
    func testScoringSelectsHighestContainingZoneAndStoresRevision() throws {
        let targetID = try TargetDefinitionID("target-bullseye")
        let target = ScoringTarget(
            targetDefinitionID: targetID,
            targetDefinitionRevision: 3,
            zones: [
                CircularScoringZone(
                    id: "outer",
                    label: "Outer",
                    scoreValue: 5,
                    center: PhysicalPoint(x: 0, y: 0, unit: .inch),
                    radius: 5
                ),
                CircularScoringZone(
                    id: "inner",
                    label: "Inner",
                    scoreValue: 10,
                    center: PhysicalPoint(x: 0, y: 0, unit: .inch),
                    radius: 1
                )
            ]
        )

        let score = try XCTUnwrap(
            TargetScoringEngine().score(
                PhysicalPoint(x: 0.5, y: 0, unit: .inch),
                using: target
            )
        )

        XCTAssertEqual(score.zoneID, "inner")
        XCTAssertEqual(score.value, 10)
        XCTAssertEqual(score.targetDefinitionRevision, 3)
        XCTAssertEqual(score.shotScore.targetDefinitionRevision, 3)
    }

    func testBoundaryUncertaintyMarksScoreReviewable() throws {
        let target = ScoringTarget(
            targetDefinitionID: try TargetDefinitionID("target-bullseye"),
            targetDefinitionRevision: 1,
            zones: [
                CircularScoringZone(
                    id: "ten-ring",
                    label: "10",
                    scoreValue: 10,
                    center: PhysicalPoint(x: 0, y: 0, unit: .inch),
                    radius: 1
                )
            ],
            scoreUncertaintyMargin: 0.05
        )

        let score = try XCTUnwrap(
            TargetScoringEngine().score(
                PhysicalPoint(x: 0.97, y: 0, unit: .inch),
                using: target
            )
        )

        XCTAssertTrue(score.reviewable)
    }

    func testOutsideAllZonesReturnsNoScore() throws {
        let target = ScoringTarget(
            targetDefinitionID: try TargetDefinitionID("target-bullseye"),
            targetDefinitionRevision: 1,
            zones: [
                CircularScoringZone(
                    id: "outer",
                    label: "Outer",
                    scoreValue: 5,
                    center: PhysicalPoint(x: 0, y: 0, unit: .inch),
                    radius: 1
                )
            ]
        )

        XCTAssertNil(
            TargetScoringEngine().score(
                PhysicalPoint(x: 2, y: 0, unit: .inch),
                using: target
            )
        )
    }
}
