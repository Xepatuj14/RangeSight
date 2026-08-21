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

    func testRepositoryPersistsCorrectedShotFinalAndOriginalCoordinates() async throws {
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

        var correctionState = ImpactCorrectionState()
        let detected = try correctionState.ingestDetectorEvent(
            id: try ShotID("shot-1"),
            stringID: stringID,
            eventID: "event-1",
            coordinate: try NormalizedTargetCoordinate(x: 0.5, y: 0.5),
            confidence: 0.91,
            timestamp: timestamp
        )
        _ = try correctionState.moveImpact(id: detected.id, to: try NormalizedTargetCoordinate(x: 0.57, y: 0.47))

        let correctedShot = try XCTUnwrap(correctionState.shotsForPersistence().first)
        try await repository.upsertShot(correctedShot)

        let reloadedShots = try await repository.shots(stringID: stringID)
        let reloaded = try XCTUnwrap(reloadedShots.first)
        XCTAssertEqual(reloaded.normalized, try NormalizedTargetCoordinate(x: 0.57, y: 0.47))
        XCTAssertEqual(reloaded.originalNormalized, try NormalizedTargetCoordinate(x: 0.5, y: 0.5))
        XCTAssertEqual(reloaded.source, .corrected)
        XCTAssertTrue(reloaded.corrected)
    }

    func testRepositoryPersistsDeletedImpactHistoryWithoutAcceptedShot() async throws {
        let repository = LocalRangeSightRepository(storeURL: temporaryStoreURL())
        let timestamp = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-20T12:00:00Z"))
        let ids = try await createSessionAndString(repository: repository, timestamp: timestamp)
        var correctionState = ImpactCorrectionState()
        let rawCoordinate = try NormalizedTargetCoordinate(x: 0.41, y: 0.62)
        let detected = try correctionState.ingestDetectorEvent(
            id: try ShotID("shot-deleted"),
            stringID: ids.stringID,
            eventID: "event-deleted",
            coordinate: rawCoordinate,
            confidence: 0.91,
            timestamp: timestamp
        )
        _ = try correctionState.deleteImpact(id: detected.id)

        try await repository.replaceImpactCorrectionState(correctionState, stringID: ids.stringID)

        let reloadedHistory = try await repository.impactCorrectionHistory(stringID: ids.stringID)
        let reloadedState = try await repository.impactCorrectionState(stringID: ids.stringID)
        let scoringShots = try await repository.shots(stringID: ids.stringID)

        XCTAssertEqual(reloadedHistory.count, 1)
        XCTAssertEqual(reloadedHistory.first?.id, detected.id)
        XCTAssertEqual(reloadedHistory.first?.rawEvidence?.coordinate, rawCoordinate)
        XCTAssertEqual(reloadedHistory.first?.rawEvidence?.confidence, 0.91)
        XCTAssertEqual(reloadedHistory.first?.state, .deleted)
        XCTAssertEqual(reloadedHistory.first?.provenance, .userDeleted)
        XCTAssertEqual(reloadedState.acceptedImpacts, [])
        XCTAssertEqual(scoringShots, [])
    }

    func testRepositoryPersistsMovedImpactRawAndFinalCoordinates() async throws {
        let repository = LocalRangeSightRepository(storeURL: temporaryStoreURL())
        let timestamp = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-20T12:00:00Z"))
        let ids = try await createSessionAndString(repository: repository, timestamp: timestamp)
        var correctionState = ImpactCorrectionState()
        let rawCoordinate = try NormalizedTargetCoordinate(x: 0.5, y: 0.5)
        let finalCoordinate = try NormalizedTargetCoordinate(x: 0.57, y: 0.47)
        let detected = try correctionState.ingestDetectorEvent(
            id: try ShotID("shot-moved"),
            stringID: ids.stringID,
            eventID: "event-moved",
            coordinate: rawCoordinate,
            confidence: 0.89,
            timestamp: timestamp
        )
        _ = try correctionState.moveImpact(id: detected.id, to: finalCoordinate)

        try await repository.replaceImpactCorrectionState(correctionState, stringID: ids.stringID)

        let reloadedState = try await repository.impactCorrectionState(stringID: ids.stringID)
        let reloadedImpact = try XCTUnwrap(reloadedState.impacts.first)
        let acceptedImpact = try XCTUnwrap(reloadedState.acceptedImpacts.first)

        XCTAssertEqual(reloadedImpact.id, detected.id)
        XCTAssertEqual(reloadedImpact.rawEvidence?.coordinate, rawCoordinate)
        XCTAssertEqual(reloadedImpact.rawEvidence?.confidence, 0.89)
        XCTAssertEqual(reloadedImpact.finalCoordinate, finalCoordinate)
        XCTAssertEqual(reloadedImpact.provenance, .userMoved)
        XCTAssertEqual(acceptedImpact.finalCoordinate, finalCoordinate)

        let reloadedShots = try await repository.shots(stringID: ids.stringID)
        let scoringShot = try XCTUnwrap(reloadedShots.first)
        XCTAssertEqual(scoringShot.id, detected.id)
        XCTAssertEqual(scoringShot.normalized, finalCoordinate)
        XCTAssertEqual(scoringShot.originalNormalized, rawCoordinate)
        XCTAssertEqual(scoringShot.source, .corrected)
    }

    func testRepositoryPersistsManualImpactWithoutDetectorEvidence() async throws {
        let repository = LocalRangeSightRepository(storeURL: temporaryStoreURL())
        let timestamp = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-20T12:00:00Z"))
        let ids = try await createSessionAndString(repository: repository, timestamp: timestamp)
        var correctionState = ImpactCorrectionState()
        let finalCoordinate = try NormalizedTargetCoordinate(x: 0.62, y: 0.41)
        let manual = try correctionState.manuallyAddImpact(
            stringID: ids.stringID,
            coordinate: finalCoordinate,
            timestamp: timestamp.addingTimeInterval(1)
        )

        try await repository.replaceImpactCorrectionState(correctionState, stringID: ids.stringID)

        let reloadedHistory = try await repository.impactCorrectionHistory(stringID: ids.stringID)
        let reloadedState = try await repository.impactCorrectionState(stringID: ids.stringID)
        let reloadedImpact = try XCTUnwrap(reloadedHistory.first)
        let acceptedImpact = try XCTUnwrap(reloadedState.acceptedImpacts.first)

        XCTAssertEqual(reloadedImpact.id, manual.id)
        XCTAssertEqual(reloadedImpact.finalCoordinate, finalCoordinate)
        XCTAssertEqual(reloadedImpact.provenance, .userAdded)
        XCTAssertNil(reloadedImpact.rawEvidence)
        XCTAssertEqual(acceptedImpact.finalCoordinate, finalCoordinate)

        let reloadedShots = try await repository.shots(stringID: ids.stringID)
        let scoringShot = try XCTUnwrap(reloadedShots.first)
        XCTAssertEqual(scoringShot.source, .manualAdded)
        XCTAssertEqual(scoringShot.confidence, 0)
        XCTAssertNil(scoringShot.originalNormalized)
    }

    func testRepositoryPersistsUserConfirmedMediumCandidateEvidence() async throws {
        let repository = LocalRangeSightRepository(storeURL: temporaryStoreURL())
        let timestamp = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-20T12:00:00Z"))
        let ids = try await createSessionAndString(repository: repository, timestamp: timestamp)
        var correctionState = ImpactCorrectionState()
        let rawCoordinate = try NormalizedTargetCoordinate(x: 0.44, y: 0.56)
        let raw = try RawImpactEvidence(
            detectorEventID: "event-medium",
            candidateID: "candidate-medium",
            coordinate: rawCoordinate,
            confidence: 0.72,
            timestamp: timestamp
        )

        correctionState.addMediumCandidate(raw)
        let confirmed = try correctionState.confirmMediumCandidate(
            candidateID: "candidate-medium",
            as: try ShotID("shot-confirmed"),
            stringID: ids.stringID,
            timestamp: timestamp.addingTimeInterval(1)
        )

        try await repository.replaceImpactCorrectionState(correctionState, stringID: ids.stringID)

        let reloadedState = try await repository.impactCorrectionState(stringID: ids.stringID)
        let reloadedImpact = try XCTUnwrap(reloadedState.impacts.first)

        XCTAssertEqual(reloadedImpact.id, confirmed.id)
        XCTAssertEqual(reloadedImpact.rawEvidence?.detectorEventID, "event-medium")
        XCTAssertEqual(reloadedImpact.rawEvidence?.candidateID, "candidate-medium")
        XCTAssertEqual(reloadedImpact.rawEvidence?.coordinate, rawCoordinate)
        XCTAssertEqual(reloadedImpact.rawEvidence?.confidence, 0.72)
        XCTAssertEqual(reloadedImpact.provenance, .userConfirmedCandidate)
        XCTAssertEqual(reloadedState.acceptedImpacts.first?.finalCoordinate, rawCoordinate)
    }

    func testRepositoryMigratesVersionOneStoreWithEmptyCorrectionHistory() async throws {
        let storeURL = temporaryStoreURL()
        let directory = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacyJSON = """
        {
          "schemaVersion": 1,
          "firearmProfiles": [],
          "targetDefinitions": [],
          "rangeSessions": [],
          "rangeStrings": [],
          "shots": [],
          "detectionDiagnostics": [],
          "sessionAssets": []
        }
        """
        let legacyData = try XCTUnwrap(legacyJSON.data(using: .utf8))
        try legacyData.write(to: storeURL)
        let repository = LocalRangeSightRepository(storeURL: storeURL)

        let migrated = try await repository.loadStore()

        XCTAssertEqual(migrated.schemaVersion, PersistenceSchema.currentVersion)
        XCTAssertEqual(migrated.impactCorrectionHistory, [])
    }

    func testRepositoryRejectsMalformedStoreWithoutFabricatingData() async throws {
        let storeURL = temporaryStoreURL()
        let directory = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let malformedData = try XCTUnwrap("{ not-json".data(using: .utf8))
        try malformedData.write(to: storeURL)
        let repository = LocalRangeSightRepository(storeURL: storeURL)

        do {
            _ = try await repository.loadStore()
            XCTFail("Expected malformed JSON to fail.")
        } catch is DecodingError {
            // Expected.
        } catch {
            XCTFail("Expected decoding error, got \(error).")
        }
    }

    func testRepositoryRejectsFutureSchemaOnLoadWithoutDeletingStore() async throws {
        let storeURL = temporaryStoreURL()
        let directory = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let futureJSON = """
        {
          "schemaVersion": \(PersistenceSchema.currentVersion + 1),
          "firearmProfiles": [],
          "targetDefinitions": [],
          "rangeSessions": [],
          "rangeStrings": [],
          "shots": [],
          "impactCorrectionHistory": [],
          "detectionDiagnostics": [],
          "sessionAssets": []
        }
        """
        let futureData = try XCTUnwrap(futureJSON.data(using: .utf8))
        try futureData.write(to: storeURL)
        let repository = LocalRangeSightRepository(storeURL: storeURL)

        do {
            _ = try await repository.loadStore()
            XCTFail("Expected future schema to fail.")
        } catch PersistenceError.unsupportedSchemaVersion(let version) {
            XCTAssertEqual(version, PersistenceSchema.currentVersion + 1)
            XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))
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

    private func createSessionAndString(
        repository: LocalRangeSightRepository,
        timestamp: Date
    ) async throws -> (sessionID: RangeSessionID, stringID: RangeStringID) {
        let sessionID = try RangeSessionID("session-1")
        let stringID = try RangeStringID("string-1")
        let targetID = try TargetDefinitionID("target-1")

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

        return (sessionID, stringID)
    }
}
