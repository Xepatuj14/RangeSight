import XCTest
@testable import RangeSightCore

final class NavigationStateTests: XCTestCase {
    func testAllScreensHaveActionsAndUniqueIDs() {
        var ids = Set<AppScreenID>()

        for screen in AppNavigation.screens {
            XCTAssertFalse(ids.contains(screen.id), "Duplicate screen id: \(screen.id)")
            ids.insert(screen.id)
            XCTAssertFalse(screen.title.isEmpty)
            XCTAssertFalse(screen.actions.isEmpty)

            for action in screen.actions {
                XCTAssertNotNil(AppNavigation.action(from: screen.id, to: action.destination))
            }
        }

        XCTAssertEqual(AppNavigation.screen(for: .home).id, .home)
        XCTAssertNil(AppNavigation.action(from: .home, to: .liveMonitor))
    }

    func testGuidedHappyPathReturnsHome() throws {
        var workflow = RangeSightWorkflow()

        workflow.beginNewSession(sessionID: try RangeSessionID("session-nav"), createdAt: referenceDate)
        XCTAssertEqual(workflow.route, .sessionSetup)
        XCTAssertEqual(workflow.domainState, .setup)

        workflow.selectFirearm(firearmProfile(id: "firearm-nav", nickname: "Compact 9"))
        workflow.selectTarget(SupportedTargetCatalog.bullseyePracticeTargetDefinition)
        try workflow.selectDistance(15, unit: .yard)
        try workflow.continueToCamera()
        XCTAssertEqual(workflow.route, .cameraSetup)
        XCTAssertEqual(workflow.domainState, .preview)

        workflow.lockTarget(at: referenceDate.addingTimeInterval(5))
        XCTAssertEqual(workflow.route, .ready)
        XCTAssertEqual(workflow.domainState, .locked)

        workflow.startString(id: try RangeStringID("string-nav-1"))
        XCTAssertEqual(workflow.route, .liveString)
        XCTAssertEqual(workflow.domainState, .monitoring)

        workflow.endString()
        XCTAssertEqual(workflow.route, .stringReview)
        XCTAssertEqual(workflow.domainState, .reviewing)

        workflow.saveString(SavedStringSummary(id: try RangeStringID("string-nav-1"), index: 1, acceptedShotCount: 2, totalScore: 18))
        XCTAssertEqual(workflow.route, .stringSummary)
        XCTAssertEqual(workflow.domainState, .saved)

        workflow.endSession()
        XCTAssertEqual(workflow.route, .sessionSummary)

        workflow.done()
        XCTAssertEqual(workflow.route, .home)
        XCTAssertEqual(workflow.domainState, .idle)
        XCTAssertNil(workflow.draft)
    }

    func testBackNavigationRoutesAreExplicit() throws {
        var workflow = configuredWorkflow()

        try workflow.continueToCamera()
        workflow.back()
        XCTAssertEqual(workflow.route, .sessionSetup)

        try workflow.continueToCamera()
        workflow.lockTarget(at: referenceDate)
        workflow.back()
        XCTAssertEqual(workflow.route, .cameraSetup)

        workflow.openHistory()
        workflow.openHistoryDetail()
        workflow.back()
        XCTAssertEqual(workflow.route, .history)
        workflow.back()
        XCTAssertEqual(workflow.route, .home)

        workflow.openSettings()
        workflow.back()
        XCTAssertEqual(workflow.route, .home)
    }

    func testActiveStringBackRequiresExplicitEndOrContinuePolicy() throws {
        var workflow = configuredWorkflow()
        try workflow.continueToCamera()
        workflow.lockTarget(at: referenceDate)
        workflow.startString(id: try RangeStringID("string-live"))

        XCTAssertEqual(workflow.exitPolicy, .confirmEndOrContinue)
        workflow.back()
        XCTAssertEqual(workflow.route, .liveString)
        XCTAssertEqual(workflow.domainState, .monitoring)

        workflow.pause()
        XCTAssertEqual(workflow.exitPolicy, .confirmEndOrContinue)
    }

    func testDistanceSelectionValidatesAndPersistsThroughHistoryAnalytics() async throws {
        var workflow = configuredWorkflow()
        try workflow.selectDistance(15, unit: .yard)
        XCTAssertEqual(workflow.draft?.distance, 15)

        let repository = LocalRangeSightRepository(storeURL: temporaryStoreURL())
        let request = try saveRequest(from: workflow, stringID: try RangeStringID("string-distance"))
        try await ProductionSessionSaveCoordinator().save(request, to: repository)

        let session = try await repository.rangeSession(id: request.session.id)
        XCTAssertEqual(session?.distance, 15)
        XCTAssertEqual(session?.distanceUnit, .yard)

        let analytics = try await SessionAnalyticsRepositoryService().analytics(repository: repository)
        XCTAssertEqual(analytics.historyItems.first?.distance, 15)
        XCTAssertEqual(analytics.historyItems.first?.firearmName, "Compact 9")
        XCTAssertEqual(analytics.historyItems.first?.targetName, SupportedTargetCatalog.bullseyePracticeTargetDefinition.name)
    }

    func testCustomDistanceRejectsInvalidValues() throws {
        var draft = SessionDraft(sessionID: try RangeSessionID("session-distance"), createdAt: referenceDate)

        XCTAssertThrowsError(try draft.selectDistance(0))
        XCTAssertThrowsError(try draft.selectDistance(-7))
        XCTAssertThrowsError(try draft.selectDistance(.nan))

        try draft.selectDistance(25)
        XCTAssertEqual(draft.distance, 25)
    }

    func testTargetAndFirearmChangesStayOnDraft() throws {
        var workflow = RangeSightWorkflow()
        workflow.beginNewSession(sessionID: try RangeSessionID("session-values"), createdAt: referenceDate)
        let firearm = firearmProfile(id: "firearm-values", nickname: "Range Rifle")
        let target = SupportedTargetCatalog.bullseyePracticeTargetDefinition

        workflow.selectFirearm(firearm)
        workflow.selectTarget(target)
        try workflow.selectDistance(20)

        XCTAssertEqual(workflow.draft?.selectedFirearm, firearm)
        XCTAssertEqual(workflow.draft?.selectedTarget, target)
        XCTAssertEqual(workflow.draft?.distance, 20)
    }

    func testCleanStoreHasNoMockHistory() async throws {
        let repository = LocalRangeSightRepository(storeURL: temporaryStoreURL())
        let analytics = try await SessionAnalyticsRepositoryService().analytics(repository: repository)

        XCTAssertTrue(analytics.historyItems.isEmpty)
    }

    func testShootAnotherStringRetainsSessionMetadataAndCreatesNewStringSlot() throws {
        var workflow = configuredWorkflow()
        try workflow.continueToCamera()
        workflow.lockTarget(at: referenceDate)
        workflow.startString(id: try RangeStringID("string-one"))
        workflow.endString()
        workflow.saveString(SavedStringSummary(id: try RangeStringID("string-one"), index: 1, acceptedShotCount: 1, totalScore: 10))

        let sessionID = workflow.draft?.sessionID
        let firearm = workflow.draft?.selectedFirearm
        let target = workflow.draft?.selectedTarget
        let distance = workflow.draft?.distance

        workflow.shootAnotherString()

        XCTAssertEqual(workflow.route, .ready)
        XCTAssertEqual(workflow.domainState, .locked)
        XCTAssertEqual(workflow.draft?.sessionID, sessionID)
        XCTAssertEqual(workflow.draft?.selectedFirearm, firearm)
        XCTAssertEqual(workflow.draft?.selectedTarget, target)
        XCTAssertEqual(workflow.draft?.distance, distance)

        workflow.startString(id: try RangeStringID("string-two"))
        XCTAssertEqual(workflow.activeStringIndex, 2)
        XCTAssertEqual(workflow.activeStringID, try RangeStringID("string-two"))
    }

    func testEndSessionAggregatesSavedStringSummaries() throws {
        var workflow = configuredWorkflow()
        try workflow.continueToCamera()
        workflow.lockTarget(at: referenceDate)
        workflow.startString(id: try RangeStringID("string-one"))
        workflow.endString()
        workflow.saveString(SavedStringSummary(id: try RangeStringID("string-one"), index: 1, acceptedShotCount: 2, totalScore: 18))
        workflow.shootAnotherString()
        workflow.startString(id: try RangeStringID("string-two"))
        workflow.endString()
        workflow.saveString(SavedStringSummary(id: try RangeStringID("string-two"), index: 2, acceptedShotCount: 3, totalScore: 24))
        workflow.endSession()

        XCTAssertEqual(workflow.route, .sessionSummary)
        XCTAssertEqual(workflow.savedStrings.map(\.acceptedShotCount).reduce(0, +), 5)
        XCTAssertEqual(workflow.savedStrings.compactMap(\.totalScore).reduce(0, +), 42)
    }

    func testReviewBackRequiresDiscardConfirmationWhenUnsaved() throws {
        var workflow = configuredWorkflow()
        try workflow.continueToCamera()
        workflow.lockTarget(at: referenceDate)
        workflow.startString(id: try RangeStringID("string-review"))
        workflow.endString()
        workflow.markReviewChanged()

        XCTAssertEqual(workflow.route, .stringReview)
        XCTAssertEqual(workflow.exitPolicy, .confirmDiscardString)
        workflow.back()
        XCTAssertEqual(workflow.route, .stringReview)
    }

    private var referenceDate: Date {
        Date(timeIntervalSince1970: 1_785_000_000)
    }

    private func configuredWorkflow() throws -> RangeSightWorkflow {
        var workflow = RangeSightWorkflow()
        workflow.beginNewSession(sessionID: try RangeSessionID("session-configured"), createdAt: referenceDate)
        workflow.selectFirearm(firearmProfile(id: "firearm-configured", nickname: "Compact 9"))
        workflow.selectTarget(SupportedTargetCatalog.bullseyePracticeTargetDefinition)
        try workflow.selectDistance(15, unit: .yard)
        return workflow
    }

    private func firearmProfile(id: String, nickname: String) -> FirearmProfile {
        FirearmProfile(
            id: FirearmProfileID(rawValue: id),
            nickname: nickname,
            category: .handgun,
            caliber: "9mm",
            notes: nil,
            createdAt: referenceDate
        )
    }

    private func saveRequest(from workflow: RangeSightWorkflow, stringID: RangeStringID) throws -> SessionSaveRequest {
        let draft = try XCTUnwrap(workflow.draft)
        let firearm = try XCTUnwrap(draft.selectedFirearm)
        let target = try XCTUnwrap(draft.selectedTarget)
        let session = RangeSession(
            id: draft.sessionID,
            startedAt: draft.createdAt,
            endedAt: nil,
            distance: draft.distance,
            distanceUnit: draft.distanceUnit,
            firearmID: firearm.id,
            targetDefinitionID: target.id,
            device: DeviceMetadata(platform: .iOS, modelName: "iPhone", osVersion: "26.0", appVersion: "0.1.0")
        )
        let rangeString = RangeString(
            id: stringID,
            sessionID: draft.sessionID,
            index: 1,
            baselineAssetID: nil,
            startedAt: draft.createdAt.addingTimeInterval(10),
            endedAt: draft.createdAt.addingTimeInterval(70)
        )
        var correctionState = ImpactCorrectionState()
        try correctionState.manuallyAddImpact(
            stringID: stringID,
            coordinate: NormalizedTargetCoordinate(x: 0.5, y: 0.5),
            timestamp: draft.createdAt.addingTimeInterval(20)
        )
        return try SessionSaveRequest(
            session: session,
            rangeString: rangeString,
            firearmProfile: firearm,
            targetDefinition: target,
            correctionState: correctionState
        )
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("rangesight-store.json")
    }
}
