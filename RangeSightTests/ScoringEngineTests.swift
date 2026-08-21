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

    func testSupportedBullseyeScoresCenterBoundaryAndOutsideZones() throws {
        let engine = AcceptedImpactStringScoringEngine()
        let stringID = try RangeStringID("string-1")
        var state = ImpactCorrectionState()
        _ = try state.manuallyAddImpact(
            stringID: stringID,
            coordinate: try NormalizedTargetCoordinate(x: 0.5, y: 0.5),
            timestamp: Date(timeIntervalSince1970: 1)
        )
        _ = try state.manuallyAddImpact(
            stringID: stringID,
            coordinate: try NormalizedTargetCoordinate(x: 0.75, y: 0.5),
            timestamp: Date(timeIntervalSince1970: 2)
        )
        _ = try state.manuallyAddImpact(
            stringID: stringID,
            coordinate: try NormalizedTargetCoordinate(x: 1, y: 1),
            timestamp: Date(timeIntervalSince1970: 3)
        )

        let result = try engine.score(
            correctionState: state,
            targetDefinitionID: SupportedTargetCatalog.bullseyePracticeID
        )

        XCTAssertEqual(result.status, .scored)
        XCTAssertEqual(result.targetDefinitionRevision, 1)
        XCTAssertEqual(result.perImpactScores.map(\.zoneID), ["ten-ring", "eight-ring", nil])
        XCTAssertEqual(result.perImpactScores.map(\.scoreValue), [10.0, 8.0, nil])
        XCTAssertEqual(result.perImpactScores.map(\.status), [.scored, .scored, .miss])
        XCTAssertEqual(result.totalScore, 18.0)
        XCTAssertEqual(result.maximumPossibleScore, 30.0)
        XCTAssertEqual(result.acceptedImpactCount, 3)
        XCTAssertEqual(result.scoredImpactCount, 2)
        XCTAssertEqual(result.missCount, 1)
    }

    func testStringScoringUsesMovedFinalCoordinateAndIgnoresRawDetectorCoordinate() throws {
        let engine = AcceptedImpactStringScoringEngine()
        let stringID = try RangeStringID("string-1")
        var state = ImpactCorrectionState()
        let detected = try state.ingestDetectorEvent(
            id: try ShotID("shot-1"),
            stringID: stringID,
            eventID: "event-1",
            coordinate: try NormalizedTargetCoordinate(x: 0.5, y: 0.5),
            confidence: 0.92,
            timestamp: Date(timeIntervalSince1970: 1)
        )
        _ = try state.moveImpact(id: detected.id, to: try NormalizedTargetCoordinate(x: 0.75, y: 0.5))

        let result = try engine.score(
            correctionState: state,
            targetDefinitionID: SupportedTargetCatalog.bullseyePracticeID
        )
        let score = try XCTUnwrap(result.perImpactScores.first)

        XCTAssertEqual(state.impacts.first?.rawEvidence?.coordinate, try NormalizedTargetCoordinate(x: 0.5, y: 0.5))
        XCTAssertEqual(score.acceptedNormalizedCoordinate, try NormalizedTargetCoordinate(x: 0.75, y: 0.5))
        XCTAssertEqual(score.zoneID, "eight-ring")
        XCTAssertEqual(score.scoreValue, 8.0)
    }

    func testStringScoringExcludesDeletedImpactFromScoreAndGroup() throws {
        let engine = AcceptedImpactStringScoringEngine()
        let stringID = try RangeStringID("string-1")
        var state = ImpactCorrectionState()
        let first = try state.ingestDetectorEvent(
            id: try ShotID("shot-1"),
            stringID: stringID,
            eventID: "event-1",
            coordinate: try NormalizedTargetCoordinate(x: 0.5, y: 0.5),
            confidence: 0.92,
            timestamp: Date(timeIntervalSince1970: 1)
        )
        _ = try state.ingestDetectorEvent(
            id: try ShotID("shot-2"),
            stringID: stringID,
            eventID: "event-2",
            coordinate: try NormalizedTargetCoordinate(x: 0.75, y: 0.5),
            confidence: 0.88,
            timestamp: Date(timeIntervalSince1970: 2)
        )
        _ = try state.deleteImpact(id: first.id)

        let result = try engine.score(
            correctionState: state,
            targetDefinitionID: SupportedTargetCatalog.bullseyePracticeID
        )

        XCTAssertEqual(state.impacts.count, 2)
        XCTAssertEqual(state.acceptedImpacts.count, 1)
        XCTAssertEqual(result.acceptedImpactCount, 1)
        XCTAssertEqual(result.perImpactScores.map(\.id), [try ShotID("shot-2")])
        XCTAssertEqual(result.totalScore, 8.0)
        XCTAssertEqual(result.groupMetrics?.shotCount, 1)
    }

    func testManualAddScoresWithoutRawDetectorEvidence() throws {
        let engine = AcceptedImpactStringScoringEngine()
        let stringID = try RangeStringID("string-1")
        var state = ImpactCorrectionState()
        let added = try state.manuallyAddImpact(
            stringID: stringID,
            coordinate: try NormalizedTargetCoordinate(x: 0.5, y: 0.5),
            timestamp: Date(timeIntervalSince1970: 1)
        )

        let result = try engine.score(
            correctionState: state,
            targetDefinitionID: SupportedTargetCatalog.bullseyePracticeID
        )

        XCTAssertNil(added.rawEvidence)
        XCTAssertEqual(result.perImpactScores.first?.id, added.id)
        XCTAssertEqual(result.perImpactScores.first?.scoreValue, 10.0)
    }

    func testMediumCandidateScoresOnlyAfterConfirmation() throws {
        let engine = AcceptedImpactStringScoringEngine()
        let stringID = try RangeStringID("string-1")
        var state = ImpactCorrectionState()
        state.addMediumCandidate(
            try RawImpactEvidence(
                detectorEventID: "event-medium",
                candidateID: "candidate-medium",
                coordinate: try NormalizedTargetCoordinate(x: 0.5, y: 0.5),
                confidence: 0.72,
                timestamp: Date(timeIntervalSince1970: 1)
            )
        )

        let before = try engine.score(
            correctionState: state,
            targetDefinitionID: SupportedTargetCatalog.bullseyePracticeID
        )
        _ = try state.confirmMediumCandidate(
            candidateID: "candidate-medium",
            as: try ShotID("shot-confirmed"),
            stringID: stringID,
            timestamp: Date(timeIntervalSince1970: 2)
        )
        let after = try engine.score(
            correctionState: state,
            targetDefinitionID: SupportedTargetCatalog.bullseyePracticeID
        )

        XCTAssertEqual(before.status, .noAcceptedImpacts)
        XCTAssertEqual(after.status, .scored)
        XCTAssertEqual(after.perImpactScores.first?.scoreValue, 10.0)
    }

    func testUnsupportedTargetReturnsUnavailableWithoutFabricatingScore() throws {
        let engine = AcceptedImpactStringScoringEngine()
        let stringID = try RangeStringID("string-1")
        var state = ImpactCorrectionState()
        _ = try state.manuallyAddImpact(
            stringID: stringID,
            coordinate: try NormalizedTargetCoordinate(x: 0.5, y: 0.5),
            timestamp: Date(timeIntervalSince1970: 1)
        )

        let result = try engine.score(
            correctionState: state,
            targetDefinitionID: try TargetDefinitionID("generic-unsupported-target")
        )

        XCTAssertEqual(result.status, .unavailable)
        XCTAssertEqual(result.acceptedImpactCount, 1)
        XCTAssertEqual(result.scoredImpactCount, 0)
        XCTAssertNil(result.totalScore)
        XCTAssertEqual(result.perImpactScores.first?.status, .unavailable)
        XCTAssertNil(result.perImpactScores.first?.scoreValue)
    }

    func testScoredShotsForPersistenceCarryTargetRevision() throws {
        let engine = AcceptedImpactStringScoringEngine()
        let stringID = try RangeStringID("string-1")
        var state = ImpactCorrectionState()
        _ = try state.manuallyAddImpact(
            stringID: stringID,
            coordinate: try NormalizedTargetCoordinate(x: 0.5, y: 0.5),
            timestamp: Date(timeIntervalSince1970: 1)
        )

        let shots = try engine.shotsForPersistence(
            correctionState: state,
            targetDefinitionID: SupportedTargetCatalog.bullseyePracticeID
        )
        let shot = try XCTUnwrap(shots.first)

        XCTAssertEqual(shot.score?.value, 10.0)
        XCTAssertEqual(shot.score?.targetDefinitionRevision, 1)
        XCTAssertFalse(shot.score?.reviewable ?? true)
    }

    func testAudioSupportDoesNotAffectPointValue() throws {
        let target = try XCTUnwrap(SupportedTargetCatalog.scoringTarget(for: SupportedTargetCatalog.bullseyePracticeID))
        let dimensions = try XCTUnwrap(target.physicalDimensions)
        let coordinate = try NormalizedTargetCoordinate(x: 0.5, y: 0.5)
        let physical = TargetCoordinateConverter.physicalPoint(from: coordinate, dimensions: dimensions)
        let visualOnly = try XCTUnwrap(TargetScoringEngine().score(physical, using: target))
        let audioAssisted = try LiveImpactEvent(
            id: "live-impact-1",
            shotIndex: 1,
            frameSequenceIndex: 10,
            timestamp: 1,
            normalizedCoordinate: try NormalizedImagePoint(x: coordinate.x, y: coordinate.y),
            confidence: 0.93,
            confidenceBand: .high,
            temporalCandidateID: "temporal-1",
            audioAssisted: true,
            supportingAudioEventID: "audio-1",
            audioImpulseStrength: 2
        )
        let audioPhysical = TargetCoordinateConverter.physicalPoint(
            from: try NormalizedTargetCoordinate(
                x: audioAssisted.normalizedCoordinate.x,
                y: audioAssisted.normalizedCoordinate.y
            ),
            dimensions: dimensions
        )
        let audioSupported = try XCTUnwrap(TargetScoringEngine().score(audioPhysical, using: target))

        XCTAssertEqual(visualOnly.value, 10.0)
        XCTAssertEqual(audioSupported.value, visualOnly.value)
    }
}
