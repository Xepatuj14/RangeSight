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
}
