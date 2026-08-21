import XCTest
@testable import RangeSightCore

final class SessionSaveCoordinatorTests: XCTestCase {
    func testProductionSavePersistsOneSessionWithScoredAcceptedShots() async throws {
        let repository = LocalRangeSightRepository(storeURL: temporaryStoreURL())
        let request = try makeSaveRequest()
        let coordinator = ProductionSessionSaveCoordinator()

        let result = try await coordinator.save(request, to: repository)

        let sessions = try await repository.rangeSessions()
        let strings = try await repository.rangeStrings(sessionID: request.session.id)
        let shots = try await repository.shots(stringID: request.rangeString.id)
        let history = try await repository.impactCorrectionHistory(stringID: request.rangeString.id)

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(strings.count, 1)
        XCTAssertEqual(shots.count, 3)
        XCTAssertEqual(history.count, 4)
        XCTAssertEqual(result.acceptedShotCount, 3)
        XCTAssertEqual(shots.compactMap(\.score).count, 3)
        XCTAssertEqual(sessions.first?.firearmID, request.firearmProfile?.id)
        let store = try await repository.loadStore()
        XCTAssertEqual(store.targetDefinitions.first?.revision, 1)
    }

    func testSaveReloadRoundTripPreservesCorrectionsAndExcludesDeletedFalsePositive() async throws {
        let storeURL = temporaryStoreURL()
        let repository = LocalRangeSightRepository(storeURL: storeURL)
        let request = try makeSaveRequest()
        let coordinator = ProductionSessionSaveCoordinator()

        try await coordinator.save(request, to: repository)

        let reloadedRepository = LocalRangeSightRepository(storeURL: storeURL)
        let reloadedSession = try await reloadedRepository.rangeSession(id: request.session.id)
        let reloadedStrings = try await reloadedRepository.rangeStrings(sessionID: request.session.id)
        let reloadedShots = try await reloadedRepository.shots(stringID: request.rangeString.id)
        let reloadedHistory = try await reloadedRepository.impactCorrectionHistory(stringID: request.rangeString.id)
        let expectedShotIDs = [
            try ShotID("shot-auto"),
            try ShotID("shot-moved"),
            try ShotID("manual-impact-1")
        ]
        let deletedShotID = try ShotID("shot-deleted")
        let movedShotID = try ShotID("shot-moved")
        let manualShotID = try ShotID("manual-impact-1")

        XCTAssertEqual(reloadedSession, request.session)
        XCTAssertEqual(reloadedStrings, [request.rangeString])
        XCTAssertEqual(reloadedShots.map(\.id), expectedShotIDs)
        XCTAssertFalse(reloadedShots.contains { $0.id == deletedShotID })

        let moved = try XCTUnwrap(reloadedHistory.first { $0.id == movedShotID })
        XCTAssertEqual(moved.rawEvidence?.coordinate, try NormalizedTargetCoordinate(x: 0.70, y: 0.50))
        XCTAssertEqual(moved.finalCoordinate, try NormalizedTargetCoordinate(x: 0.62, y: 0.48))
        XCTAssertEqual(moved.provenance, .userMoved)

        let manual = try XCTUnwrap(reloadedHistory.first { $0.id == manualShotID })
        XCTAssertNil(manual.rawEvidence)
        XCTAssertEqual(manual.provenance, .userAdded)

        let deleted = try XCTUnwrap(reloadedHistory.first { $0.id == deletedShotID })
        XCTAssertEqual(deleted.state, .deleted)
        XCTAssertEqual(deleted.provenance, .userDeleted)
        XCTAssertNotNil(deleted.rawEvidence)
    }

    func testDoubleSaveIsIdempotentForStableRequestIdentifiers() async throws {
        let repository = LocalRangeSightRepository(storeURL: temporaryStoreURL())
        let request = try makeSaveRequest()
        let coordinator = ProductionSessionSaveCoordinator()

        try await coordinator.save(request, to: repository)
        try await coordinator.save(request, to: repository)

        let store = try await repository.loadStore()
        XCTAssertEqual(store.rangeSessions.count, 1)
        XCTAssertEqual(store.rangeStrings.count, 1)
        XCTAssertEqual(store.shots.count, 3)
        XCTAssertEqual(store.impactCorrectionHistory.count, 4)
    }

    func testSaveFailureThrowsWithoutMutatingReviewedRequest() async throws {
        let request = try makeSaveRequest()
        let repository = FailingRangeSightRepository()
        let coordinator = ProductionSessionSaveCoordinator()

        do {
            try await coordinator.save(request, to: repository)
            XCTFail("Expected repository failure to throw.")
        } catch TestRepositoryError.writeFailed {
            let recordedWrites = await repository.writeAttempts
            XCTAssertEqual(recordedWrites, 1)
            XCTAssertEqual(request.correctionState.acceptedImpacts.count, 3)
            XCTAssertEqual(request.correctionState.impacts.count, 4)
        }
    }

    func testHistoryAnalyticsSeesNewlySavedProductionSessionAndCleanStoreIsEmpty() async throws {
        let emptyRepository = LocalRangeSightRepository(storeURL: temporaryStoreURL())
        let analyticsService = SessionAnalyticsRepositoryService()
        let emptyAnalytics = try await analyticsService.analytics(repository: emptyRepository)
        XCTAssertTrue(emptyAnalytics.historyItems.isEmpty)

        let repository = LocalRangeSightRepository(storeURL: temporaryStoreURL())
        let request = try makeSaveRequest()
        try await ProductionSessionSaveCoordinator().save(request, to: repository)

        let analytics = try await analyticsService.analytics(repository: repository)
        XCTAssertEqual(analytics.historyItems.count, 1)
        XCTAssertEqual(analytics.historyItems.first?.id, request.session.id)
        XCTAssertEqual(analytics.historyItems.first?.acceptedShotCount, 3)
    }

    func testSaveFlowStateMachineKeepsFailureRetryableAndBlocksDuplicateTap() {
        XCTAssertEqual(ReleaseSaveFlow.nextState(from: .review, event: .saveTapped), .saving)
        XCTAssertNil(ReleaseSaveFlow.nextState(from: .saving, event: .saveTapped))
        XCTAssertEqual(ReleaseSaveFlow.nextState(from: .saving, event: .saveFailed), .failed)
        XCTAssertEqual(ReleaseSaveFlow.nextState(from: .failed, event: .retry), .saving)
    }

    private func makeSaveRequest() throws -> SessionSaveRequest {
        let startedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-20T12:00:00Z"))
        let sessionID = try RangeSessionID("session-save")
        let stringID = try RangeStringID("string-save")
        let firearmID = try FirearmProfileID("firearm-range-9")
        let target = SupportedTargetCatalog.bullseyePracticeTargetDefinition
        let firearm = FirearmProfile(
            id: firearmID,
            nickname: "Range 9",
            category: .handgun,
            caliber: "9mm",
            notes: nil,
            createdAt: startedAt
        )
        let session = RangeSession(
            id: sessionID,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(120),
            distance: 7,
            distanceUnit: .yard,
            firearmID: firearmID,
            targetDefinitionID: target.id,
            device: DeviceMetadata(platform: .iOS, modelName: "iPhone", osVersion: "18.0", appVersion: "0.1.0")
        )
        let rangeString = RangeString(
            id: stringID,
            sessionID: sessionID,
            index: 1,
            baselineAssetID: nil,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(60)
        )

        return try SessionSaveRequest(
            session: session,
            rangeString: rangeString,
            firearmProfile: firearm,
            targetDefinition: target,
            correctionState: makeCorrectionState(stringID: stringID, startedAt: startedAt)
        )
    }

    private func makeCorrectionState(stringID: RangeStringID, startedAt: Date) throws -> ImpactCorrectionState {
        var state = ImpactCorrectionState()
        try state.ingestDetectorEvent(
            id: try ShotID("shot-auto"),
            stringID: stringID,
            eventID: "detector-auto",
            coordinate: try NormalizedTargetCoordinate(x: 0.50, y: 0.50),
            confidence: 0.95,
            timestamp: startedAt.addingTimeInterval(1)
        )
        try state.ingestDetectorEvent(
            id: try ShotID("shot-moved"),
            stringID: stringID,
            eventID: "detector-moved",
            coordinate: try NormalizedTargetCoordinate(x: 0.70, y: 0.50),
            confidence: 0.82,
            timestamp: startedAt.addingTimeInterval(2)
        )
        try state.moveImpact(
            id: try ShotID("shot-moved"),
            to: try NormalizedTargetCoordinate(x: 0.62, y: 0.48)
        )
        try state.manuallyAddImpact(
            stringID: stringID,
            coordinate: try NormalizedTargetCoordinate(x: 0.45, y: 0.45),
            timestamp: startedAt.addingTimeInterval(3)
        )
        try state.ingestDetectorEvent(
            id: try ShotID("shot-deleted"),
            stringID: stringID,
            eventID: "detector-deleted",
            coordinate: try NormalizedTargetCoordinate(x: 0.90, y: 0.90),
            confidence: 0.77,
            timestamp: startedAt.addingTimeInterval(4)
        )
        try state.deleteImpact(id: try ShotID("shot-deleted"))
        return state
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("rangesight-store.json")
    }
}

private enum TestRepositoryError: Error {
    case writeFailed
}

private actor FailingRangeSightRepository: RangeSightRepository {
    private(set) var writeAttempts = 0

    func loadStore() async throws -> PersistedRangeSightStore {
        PersistedRangeSightStore()
    }

    func replaceStore(_ store: PersistedRangeSightStore) async throws {
        writeAttempts += 1
        throw TestRepositoryError.writeFailed
    }

    func upsertFirearmProfile(_ profile: FirearmProfile) async throws {
        writeAttempts += 1
        throw TestRepositoryError.writeFailed
    }

    func upsertTargetDefinition(_ target: TargetDefinition) async throws {
        writeAttempts += 1
        throw TestRepositoryError.writeFailed
    }

    func upsertRangeSession(_ session: RangeSession) async throws {
        writeAttempts += 1
        throw TestRepositoryError.writeFailed
    }

    func rangeSession(id: RangeSessionID) async throws -> RangeSession? {
        nil
    }

    func rangeSessions() async throws -> [RangeSession] {
        []
    }

    func upsertRangeString(_ rangeString: RangeString) async throws {
        writeAttempts += 1
        throw TestRepositoryError.writeFailed
    }

    func rangeStrings(sessionID: RangeSessionID) async throws -> [RangeString] {
        []
    }

    func upsertShot(_ shot: Shot) async throws {
        writeAttempts += 1
        throw TestRepositoryError.writeFailed
    }

    func shots(stringID: RangeStringID) async throws -> [Shot] {
        []
    }

    func replaceImpactCorrectionState(_ state: ImpactCorrectionState, stringID: RangeStringID) async throws {
        writeAttempts += 1
        throw TestRepositoryError.writeFailed
    }

    func replaceImpactCorrectionHistory(_ impacts: [AcceptedImpact], stringID: RangeStringID) async throws {
        writeAttempts += 1
        throw TestRepositoryError.writeFailed
    }

    func impactCorrectionHistory(stringID: RangeStringID) async throws -> [AcceptedImpact] {
        []
    }

    func impactCorrectionState(stringID: RangeStringID) async throws -> ImpactCorrectionState {
        ImpactCorrectionState()
    }
}
