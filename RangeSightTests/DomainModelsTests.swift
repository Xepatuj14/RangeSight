import XCTest
@testable import RangeSightCore

final class DomainModelsTests: XCTestCase {
    func testDomainModelsRoundTripThroughSchemaVersionedRecords() throws {
        let createdAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-20T02:00:00Z"))
        let firearmID = try FirearmProfileID("firearm-1")
        let targetID = try TargetDefinitionID("target-uspsa-practice")
        let sessionID = try RangeSessionID("session-1")
        let stringID = try RangeStringID("string-1")

        let firearm = FirearmProfile(
            id: firearmID,
            nickname: "Range 9",
            category: .handgun,
            caliber: "9mm",
            notes: "Baseline profile for indoor handgun practice.",
            createdAt: createdAt
        )

        let target = TargetDefinition(
            id: targetID,
            name: "USPSA Practice Paper",
            revision: 1,
            physicalDimensions: try PhysicalDimensions(width: 18, height: 30, unit: .inch),
            scoringZones: [
                ScoringZoneDefinition(id: "a-zone", label: "A zone", scoreValue: 5, reviewMargin: 0.015)
            ],
            aimPoints: [
                AimPoint(id: "center", label: "Center", normalized: try NormalizedTargetCoordinate(x: 0.5, y: 0.5))
            ],
            supportedModes: [.genericImpact, .groupMetrics, .scoring]
        )

        let session = RangeSession(
            id: sessionID,
            startedAt: createdAt,
            endedAt: nil,
            distance: 7,
            distanceUnit: .yard,
            firearmID: firearmID,
            targetDefinitionID: targetID,
            device: DeviceMetadata(platform: .iOS, modelName: "iPhone development build", osVersion: nil, appVersion: "0.1.0")
        )

        let string = RangeString(
            id: stringID,
            sessionID: sessionID,
            index: 1,
            baselineAssetID: SessionAssetID(rawValue: "asset-baseline-1"),
            startedAt: createdAt,
            endedAt: nil
        )

        let shot = try Shot(
            id: try ShotID("shot-1"),
            stringID: stringID,
            ordinal: 1,
            timestamp: createdAt,
            normalized: try NormalizedTargetCoordinate(x: 0.52, y: 0.48),
            confidence: 0.91,
            source: .autoConfirmed,
            corrected: false
        )

        XCTAssertEqual(try DomainSerializer.payload(from: DomainSerializer.record(kind: "FirearmProfile", payload: firearm), expectedKind: "FirearmProfile"), firearm)
        XCTAssertEqual(try DomainSerializer.payload(from: DomainSerializer.record(kind: "TargetDefinition", payload: target), expectedKind: "TargetDefinition"), target)
        XCTAssertEqual(try DomainSerializer.payload(from: DomainSerializer.record(kind: "RangeSession", payload: session), expectedKind: "RangeSession"), session)
        XCTAssertEqual(try DomainSerializer.payload(from: DomainSerializer.record(kind: "RangeString", payload: string), expectedKind: "RangeString"), string)
        XCTAssertEqual(try DomainSerializer.payload(from: DomainSerializer.record(kind: "Shot", payload: shot), expectedKind: "Shot"), shot)
    }

    func testInvalidShotCoordinatesAndConfidenceFail() throws {
        XCTAssertThrowsError(try NormalizedTargetCoordinate(x: 1.2, y: 0.48))
        XCTAssertThrowsError(
            try Shot(
                id: ShotID(rawValue: "shot-1"),
                stringID: RangeStringID(rawValue: "string-1"),
                ordinal: 1,
                timestamp: Date(),
                normalized: try NormalizedTargetCoordinate(x: 0.5, y: 0.5),
                confidence: -0.01,
                source: .autoConfirmed,
                corrected: false
            )
        )
    }

    func testSerializerRejectsUnsupportedVersionAndWrongKind() {
        let record = SerializedDomainRecord(schemaVersion: 999, kind: "Shot", payload: "payload")

        XCTAssertThrowsError(try DomainSerializer.payload(from: record, expectedKind: "Shot"))
        XCTAssertThrowsError(try DomainSerializer.payload(from: SerializedDomainRecord(schemaVersion: DomainSchema.currentVersion, kind: "Shot", payload: "payload"), expectedKind: "RangeSession"))
    }

    func testManualAddCreatesAcceptedImpactWithoutRawConfidence() throws {
        let timestamp = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-20T12:00:00Z"))
        let stringID = try RangeStringID("string-1")
        var state = try correctionStateWithDetectorImpacts(count: 2, stringID: stringID, timestamp: timestamp)

        let added = try state.manuallyAddImpact(
            stringID: stringID,
            coordinate: try NormalizedTargetCoordinate(x: 0.62, y: 0.41),
            timestamp: timestamp.addingTimeInterval(3)
        )

        XCTAssertEqual(state.acceptedImpacts.count, 3)
        XCTAssertEqual(added.finalCoordinate, try NormalizedTargetCoordinate(x: 0.62, y: 0.41))
        XCTAssertEqual(added.provenance, .userAdded)
        XCTAssertNil(added.rawEvidence)
        XCTAssertEqual(state.counters.userAddedCount, 1)
    }

    func testMovePreservesRawDetectorCoordinateAndStableIdentity() throws {
        let timestamp = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-20T12:00:00Z"))
        let stringID = try RangeStringID("string-1")
        var state = ImpactCorrectionState()
        let rawCoordinate = try NormalizedTargetCoordinate(x: 0.5, y: 0.5)
        let impact = try state.ingestDetectorEvent(
            id: try ShotID("shot-1"),
            stringID: stringID,
            eventID: "event-1",
            coordinate: rawCoordinate,
            confidence: 0.91,
            timestamp: timestamp
        )

        let moved = try state.moveImpact(id: impact.id, to: try NormalizedTargetCoordinate(x: 0.57, y: 0.47))

        XCTAssertEqual(moved.id, impact.id)
        XCTAssertEqual(moved.rawEvidence?.coordinate, rawCoordinate)
        XCTAssertEqual(moved.finalCoordinate, try NormalizedTargetCoordinate(x: 0.57, y: 0.47))
        XCTAssertEqual(moved.provenance, .userMoved)
        XCTAssertEqual(state.acceptedImpacts.count, 1)
    }

    func testDeleteExcludesImpactFromAcceptedOutputButRetainsHistory() throws {
        let timestamp = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-20T12:00:00Z"))
        let stringID = try RangeStringID("string-1")
        var state = try correctionStateWithDetectorImpacts(count: 3, stringID: stringID, timestamp: timestamp)

        let deleted = try state.deleteImpact(id: try ShotID("shot-2"))

        XCTAssertEqual(deleted.state, .deleted)
        XCTAssertEqual(deleted.provenance, .userDeleted)
        XCTAssertEqual(state.acceptedImpacts.map(\.id), [try ShotID("shot-1"), try ShotID("shot-3")])
        XCTAssertEqual(state.acceptedImpacts.map(\.displayOrdinal), [1, 2])
        XCTAssertEqual(state.impacts.count, 3)
        XCTAssertEqual(state.counters.userDeletedCount, 1)
    }

    func testConfirmMediumCandidateCreatesAcceptedImpactAndRemovesCandidate() throws {
        let timestamp = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-20T12:00:00Z"))
        let stringID = try RangeStringID("string-1")
        var state = ImpactCorrectionState()
        let raw = try RawImpactEvidence(
            detectorEventID: "event-medium",
            candidateID: "candidate-medium",
            coordinate: try NormalizedTargetCoordinate(x: 0.44, y: 0.56),
            confidence: 0.72,
            timestamp: timestamp
        )

        state.addMediumCandidate(raw)
        let confirmed = try state.confirmMediumCandidate(
            candidateID: "candidate-medium",
            as: try ShotID("shot-confirmed"),
            stringID: stringID,
            timestamp: timestamp.addingTimeInterval(1)
        )

        XCTAssertEqual(confirmed.provenance, .userConfirmedCandidate)
        XCTAssertEqual(confirmed.rawEvidence?.confidence, 0.72)
        XCTAssertEqual(confirmed.finalCoordinate, try NormalizedTargetCoordinate(x: 0.44, y: 0.56))
        XCTAssertEqual(state.unresolvedMediumCandidates, [])
        XCTAssertEqual(state.acceptedImpacts.count, 1)
        XCTAssertEqual(state.counters.userConfirmedCandidateCount, 1)
    }

    func testCorrectionShotsForPersistenceUseFinalCoordinatesAndOriginalRawEvidence() throws {
        let timestamp = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-20T12:00:00Z"))
        let stringID = try RangeStringID("string-1")
        var state = ImpactCorrectionState()
        let impact = try state.ingestDetectorEvent(
            id: try ShotID("shot-1"),
            stringID: stringID,
            eventID: "event-1",
            coordinate: try NormalizedTargetCoordinate(x: 0.5, y: 0.5),
            confidence: 0.91,
            timestamp: timestamp
        )
        _ = try state.moveImpact(id: impact.id, to: try NormalizedTargetCoordinate(x: 0.58, y: 0.48))

        let shots = try state.shotsForPersistence()

        XCTAssertEqual(shots.count, 1)
        XCTAssertEqual(shots.first?.id, impact.id)
        XCTAssertEqual(shots.first?.normalized, try NormalizedTargetCoordinate(x: 0.58, y: 0.48))
        XCTAssertEqual(shots.first?.originalNormalized, try NormalizedTargetCoordinate(x: 0.5, y: 0.5))
        XCTAssertEqual(shots.first?.source, .corrected)
        XCTAssertEqual(shots.first?.corrected, true)
    }

    func testTargetDisplayGeometryMapsViewPointsToNormalizedCoordinates() throws {
        let geometry = try TargetDisplayGeometry(containerWidth: 300, containerHeight: 500, targetAspectRatio: 1)

        let center = try XCTUnwrap(try geometry.normalizedCoordinate(at: DisplayPoint(x: 150, y: 250)))
        let topLeft = try XCTUnwrap(try geometry.normalizedCoordinate(at: DisplayPoint(x: 0, y: 100)))
        let bottomRight = try XCTUnwrap(try geometry.normalizedCoordinate(at: DisplayPoint(x: 300, y: 400)))
        let outside = try geometry.normalizedCoordinate(at: DisplayPoint(x: 150, y: 50))

        XCTAssertEqual(center.x, 0.5, accuracy: 0.000001)
        XCTAssertEqual(center.y, 0.5, accuracy: 0.000001)
        XCTAssertEqual(topLeft, try NormalizedTargetCoordinate(x: 0, y: 0))
        XCTAssertEqual(bottomRight, try NormalizedTargetCoordinate(x: 1, y: 1))
        XCTAssertNil(outside)
    }

    private func correctionStateWithDetectorImpacts(
        count: Int,
        stringID: RangeStringID,
        timestamp: Date
    ) throws -> ImpactCorrectionState {
        var state = ImpactCorrectionState()

        for index in 1...count {
            try state.ingestDetectorEvent(
                id: try ShotID("shot-\(index)"),
                stringID: stringID,
                eventID: "event-\(index)",
                coordinate: try NormalizedTargetCoordinate(x: 0.4 + Double(index) * 0.04, y: 0.5),
                confidence: 0.9,
                timestamp: timestamp.addingTimeInterval(Double(index))
            )
        }

        return state
    }
}
