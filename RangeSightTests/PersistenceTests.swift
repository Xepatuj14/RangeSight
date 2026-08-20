import XCTest
@testable import RangeSightCore

final class PersistenceTests: XCTestCase {
    func testRepositoryCreatesReadsAndUpdatesSessions() async throws {
        let repository = LocalRangeSightRepository(storeURL: temporaryStoreURL())
        let targetID = try TargetDefinitionID("target-1")
        let firearmID = try FirearmProfileID("firearm-1")
        let sessionID = try RangeSessionID("session-1")

        let startedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-20T12:00:00Z"))
        let endedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-20T12:20:00Z"))

        let session = RangeSession(
            id: sessionID,
            startedAt: startedAt,
            endedAt: nil,
            distance: 7,
            distanceUnit: .yard,
            firearmID: firearmID,
            targetDefinitionID: targetID,
            device: DeviceMetadata(platform: .iOS, modelName: "iPhone", osVersion: "18.0", appVersion: "0.1.0")
        )

        try await repository.upsertRangeSession(session)
        let fetchedSession = try await repository.rangeSession(id: sessionID)
        XCTAssertEqual(fetchedSession, session)

        let updated = RangeSession(
            id: sessionID,
            startedAt: startedAt,
            endedAt: endedAt,
            distance: 7,
            distanceUnit: .yard,
            firearmID: firearmID,
            targetDefinitionID: targetID,
            device: DeviceMetadata(platform: .iOS, modelName: "iPhone", osVersion: "18.0", appVersion: "0.1.0")
        )

        try await repository.upsertRangeSession(updated)
        let fetchedSessions = try await repository.rangeSessions()
        XCTAssertEqual(fetchedSessions, [updated])
    }

    func testRepositoryPersistsStringsAndShotsInStableOrder() async throws {
        let repository = LocalRangeSightRepository(storeURL: temporaryStoreURL())
        let sessionID = try RangeSessionID("session-1")
        let stringID = try RangeStringID("string-1")
        let targetID = try TargetDefinitionID("target-1")
        let timestamp = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-20T12:00:00Z"))

        try await repository.upsertRangeSession(
            RangeSession(
                id: sessionID,
                startedAt: timestamp,
                endedAt: nil,
                distance: 10,
                distanceUnit: .yard,
                firearmID: nil,
                targetDefinitionID: targetID,
                device: DeviceMetadata(platform: .iOS, modelName: nil, osVersion: nil, appVersion: nil)
            )
        )

        try await repository.upsertRangeString(
            RangeString(
                id: stringID,
                sessionID: sessionID,
                index: 1,
                baselineAssetID: nil,
                startedAt: timestamp,
                endedAt: nil
            )
        )

        let secondShot = try Shot(
            id: try ShotID("shot-2"),
            stringID: stringID,
            ordinal: 2,
            timestamp: timestamp,
            normalized: try NormalizedTargetCoordinate(x: 0.55, y: 0.45),
            confidence: 0.9,
            source: .autoConfirmed,
            corrected: false
        )

        let firstShot = try Shot(
            id: try ShotID("shot-1"),
            stringID: stringID,
            ordinal: 1,
            timestamp: timestamp,
            normalized: try NormalizedTargetCoordinate(x: 0.5, y: 0.5),
            confidence: 0.95,
            source: .autoConfirmed,
            corrected: false
        )

        try await repository.upsertShot(secondShot)
        try await repository.upsertShot(firstShot)

        let fetchedStringIDs = try await repository.rangeStrings(sessionID: sessionID).map(\.id)
        XCTAssertEqual(fetchedStringIDs, [stringID])

        let fetchedShotIDs = try await repository.shots(stringID: stringID).map(\.id)
        XCTAssertEqual(fetchedShotIDs, [firstShot.id, secondShot.id])
    }

    func testRepositoryRejectsUnsupportedSchemaVersion() async throws {
        let repository = LocalRangeSightRepository(storeURL: temporaryStoreURL())

        try await repository.replaceStore(PersistedRangeSightStore())
        let badStore = PersistedRangeSightStore(schemaVersion: PersistenceSchema.currentVersion + 1)

        do {
            try await repository.replaceStore(badStore)
            XCTFail("Expected unsupported schema version to fail.")
        } catch PersistenceError.unsupportedSchemaVersion(let version) {
            XCTAssertEqual(version, PersistenceSchema.currentVersion + 1)
        }
    }

    func testRepositoryRejectsOrphanStringsAndShots() async throws {
        let repository = LocalRangeSightRepository(storeURL: temporaryStoreURL())
        let timestamp = Date()

        do {
            try await repository.upsertRangeString(
                RangeString(
                    id: try RangeStringID("string-1"),
                    sessionID: try RangeSessionID("missing-session"),
                    index: 1,
                    baselineAssetID: nil,
                    startedAt: timestamp,
                    endedAt: nil
                )
            )
            XCTFail("Expected missing session to fail.")
        } catch PersistenceError.missingRangeSession {
            // Expected.
        }

        do {
            try await repository.upsertShot(
                Shot(
                    id: try ShotID("shot-1"),
                    stringID: try RangeStringID("missing-string"),
                    ordinal: 1,
                    timestamp: timestamp,
                    normalized: try NormalizedTargetCoordinate(x: 0.5, y: 0.5),
                    confidence: 0.9,
                    source: .autoConfirmed,
                    corrected: false
                )
            )
            XCTFail("Expected missing string to fail.")
        } catch PersistenceError.missingRangeString {
            // Expected.
        }
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("rangesight-store.json")
    }
}
