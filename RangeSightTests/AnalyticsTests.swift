import XCTest
@testable import RangeSightCore

final class AnalyticsTests: XCTestCase {
    func testAggregatesSessionsShotsGroupsScoresAndRecords() throws {
        let store = try makeStore(
            sessions: [
                session("session-1", startedAt: try date("2026-08-01T10:00:00Z"), firearmID: firearmA, distance: 7, targetID: targetA),
                session("session-2", startedAt: try date("2026-08-02T10:00:00Z"), firearmID: firearmA, distance: 7, targetID: targetA)
            ],
            strings: [
                string("string-1", sessionID: sessionID("session-1"), index: 1, startedAt: try date("2026-08-01T10:01:00Z")),
                string("string-2", sessionID: sessionID("session-2"), index: 1, startedAt: try date("2026-08-02T10:01:00Z"))
            ],
            shots: [
                shot("shot-1", stringID: stringID("string-1"), ordinal: 1, physical: point(0, 0), score: 10),
                shot("shot-2", stringID: stringID("string-1"), ordinal: 2, physical: point(3, 0), score: 8),
                shot("shot-3", stringID: stringID("string-2"), ordinal: 1, physical: point(0, 0), score: 10),
                shot("shot-4", stringID: stringID("string-2"), ordinal: 2, physical: point(4, 0), score: 6)
            ]
        )

        let result = SessionAnalyticsEngine().analytics(for: store)

        XCTAssertEqual(result.summary.sessionCount, 2)
        XCTAssertEqual(result.summary.stringCount, 2)
        XCTAssertEqual(result.summary.acceptedShotCount, 4)
        XCTAssertEqual(try XCTUnwrap(result.summary.averageGroupSize), 3.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(result.summary.medianGroupSize), 3.5, accuracy: 0.0001)
        XCTAssertEqual(result.summary.bestGroup?.stringID, stringID("string-1"))
        XCTAssertEqual(try XCTUnwrap(result.summary.bestGroup?.value), 3, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(result.summary.averageScorePerString), 17, accuracy: 0.0001)
        XCTAssertEqual(result.summary.bestScore?.stringID, stringID("string-1"))
        XCTAssertEqual(result.summary.metricUnit, .inch)
        XCTAssertFalse(result.summary.needsMoreDataForTrendClassification)
    }

    func testFiltersByFirearmDistanceTargetAndDateRange() throws {
        let store = try makeStore(
            sessions: [
                session("session-a", startedAt: try date("2026-08-01T10:00:00Z"), firearmID: firearmA, distance: 10, targetID: targetA),
                session("session-b", startedAt: try date("2026-08-02T10:00:00Z"), firearmID: firearmB, distance: 10, targetID: targetA),
                session("session-c", startedAt: try date("2026-08-03T10:00:00Z"), firearmID: firearmA, distance: 15, targetID: targetA),
                session("session-d", startedAt: try date("2026-08-04T10:00:00Z"), firearmID: firearmA, distance: 10, targetID: targetB),
                session("session-e", startedAt: try date("2026-08-05T10:00:00Z"), firearmID: firearmA, distance: 10, targetID: targetA)
            ],
            strings: [
                string("string-a", sessionID: sessionID("session-a"), index: 1, startedAt: try date("2026-08-01T10:01:00Z")),
                string("string-b", sessionID: sessionID("session-b"), index: 1, startedAt: try date("2026-08-02T10:01:00Z")),
                string("string-c", sessionID: sessionID("session-c"), index: 1, startedAt: try date("2026-08-03T10:01:00Z")),
                string("string-d", sessionID: sessionID("session-d"), index: 1, startedAt: try date("2026-08-04T10:01:00Z")),
                string("string-e", sessionID: sessionID("session-e"), index: 1, startedAt: try date("2026-08-05T10:01:00Z"))
            ],
            shots: [
                shot("shot-a1", stringID: stringID("string-a"), ordinal: 1, physical: point(0, 0), score: 10),
                shot("shot-a2", stringID: stringID("string-a"), ordinal: 2, physical: point(2, 0), score: 8),
                shot("shot-b1", stringID: stringID("string-b"), ordinal: 1, physical: point(0, 0), score: 10),
                shot("shot-c1", stringID: stringID("string-c"), ordinal: 1, physical: point(0, 0), score: 10),
                shot("shot-d1", stringID: stringID("string-d"), ordinal: 1, physical: point(0, 0), score: 10),
                shot("shot-e1", stringID: stringID("string-e"), ordinal: 1, physical: point(0, 0), score: 10),
                shot("shot-e2", stringID: stringID("string-e"), ordinal: 2, physical: point(4, 0), score: 6)
            ]
        )

        let result = SessionAnalyticsEngine().analytics(
            for: store,
            filter: AnalyticsFilter(
                firearmID: firearmA,
                distance: 10,
                distanceUnit: .yard,
                targetDefinitionID: targetA,
                dateRange: .custom(
                    start: try date("2026-08-01T00:00:00Z"),
                    end: try date("2026-08-05T00:00:00Z")
                )
            )
        )

        XCTAssertEqual(result.historyItems.map(\.id), [sessionID("session-a")])
        XCTAssertEqual(result.summary.sessionCount, 1)
        XCTAssertEqual(result.summary.acceptedShotCount, 2)
        XCTAssertEqual(try XCTUnwrap(result.summary.averageGroupSize), 2, accuracy: 0.0001)
    }

    func testCustomDateRangeIsStartInclusiveAndEndExclusive() throws {
        let store = try makeStore(
            sessions: [
                session("start", startedAt: try date("2026-08-10T00:00:00Z"), firearmID: firearmA, distance: 7, targetID: targetA),
                session("end", startedAt: try date("2026-08-11T00:00:00Z"), firearmID: firearmA, distance: 7, targetID: targetA)
            ],
            strings: [
                string("start-string", sessionID: sessionID("start"), index: 1, startedAt: try date("2026-08-10T00:01:00Z")),
                string("end-string", sessionID: sessionID("end"), index: 1, startedAt: try date("2026-08-11T00:01:00Z"))
            ],
            shots: [
                shot("start-shot-1", stringID: stringID("start-string"), ordinal: 1, physical: point(0, 0), score: nil),
                shot("start-shot-2", stringID: stringID("start-string"), ordinal: 2, physical: point(1, 0), score: nil),
                shot("end-shot-1", stringID: stringID("end-string"), ordinal: 1, physical: point(0, 0), score: nil)
            ]
        )

        let result = SessionAnalyticsEngine().analytics(
            for: store,
            filter: AnalyticsFilter(
                dateRange: .custom(
                    start: try date("2026-08-10T00:00:00Z"),
                    end: try date("2026-08-11T00:00:00Z")
                )
            )
        )

        XCTAssertEqual(result.historyItems.map(\.id), [sessionID("start")])
    }

    func testCorrectedCoordinateAndManualAddContributeWhileDeletedFalsePositiveDoesNot() throws {
        let stringID = stringID("string-1")
        let corrected = try Shot(
            id: shotID("shot-corrected"),
            stringID: stringID,
            ordinal: 1,
            timestamp: try date("2026-08-01T10:02:00Z"),
            normalized: normalized(0.75, 0.5),
            confidence: 0.9,
            source: .corrected,
            corrected: true,
            originalNormalized: normalized(0.5, 0.5),
            score: ShotScore(value: 8, targetDefinitionRevision: 1, reviewable: false)
        )
        let manual = try Shot(
            id: shotID("shot-manual"),
            stringID: stringID,
            ordinal: 2,
            timestamp: try date("2026-08-01T10:03:00Z"),
            normalized: normalized(0.5, 0.5),
            confidence: 0,
            source: .manualAdded,
            corrected: true,
            score: ShotScore(value: 10, targetDefinitionRevision: 1, reviewable: false)
        )
        let deleted = try AcceptedImpact(
            id: shotID("shot-deleted"),
            stringID: stringID,
            createdAt: try date("2026-08-01T10:04:00Z"),
            rawEvidence: try RawImpactEvidence(
                detectorEventID: "event-deleted",
                candidateID: "event-deleted",
                coordinate: normalized(0.9, 0.9),
                confidence: 0.95,
                timestamp: try date("2026-08-01T10:04:00Z")
            ),
            finalCoordinate: normalized(0.9, 0.9),
            state: .deleted,
            provenance: .userDeleted,
            displayOrdinal: 3
        )

        let store = try makeStore(
            sessions: [session("session-1", startedAt: try date("2026-08-01T10:00:00Z"), firearmID: firearmA, distance: 7, targetID: targetA)],
            strings: [string("string-1", sessionID: sessionID("session-1"), index: 1, startedAt: try date("2026-08-01T10:01:00Z"))],
            shots: [corrected, manual],
            impactCorrectionHistory: [deleted]
        )

        let result = SessionAnalyticsEngine().analytics(for: store)

        XCTAssertEqual(result.summary.acceptedShotCount, 2)
        XCTAssertEqual(try XCTUnwrap(result.summary.averageGroupSize), 2, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(result.summary.averagePointOfImpactOffset?.x), 1, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(result.summary.averageScorePerString), 18, accuracy: 0.0001)
        XCTAssertEqual(result.detectorValidation.userDeletedCount, 1)
    }

    func testUnsupportedAndMixedTargetScoresRemainUnavailableInsteadOfZeroOrCombined() throws {
        let store = try makeStore(
            sessions: [
                session("session-a", startedAt: try date("2026-08-01T10:00:00Z"), firearmID: firearmA, distance: 7, targetID: targetA),
                session("session-b", startedAt: try date("2026-08-02T10:00:00Z"), firearmID: firearmA, distance: 7, targetID: targetB),
                session("session-c", startedAt: try date("2026-08-03T10:00:00Z"), firearmID: firearmA, distance: 7, targetID: targetA)
            ],
            strings: [
                string("string-a", sessionID: sessionID("session-a"), index: 1, startedAt: try date("2026-08-01T10:01:00Z")),
                string("string-b", sessionID: sessionID("session-b"), index: 1, startedAt: try date("2026-08-02T10:01:00Z")),
                string("string-c", sessionID: sessionID("session-c"), index: 1, startedAt: try date("2026-08-03T10:01:00Z"))
            ],
            shots: [
                shot("shot-a", stringID: stringID("string-a"), ordinal: 1, physical: point(0, 0), score: 10),
                shot("shot-b", stringID: stringID("string-b"), ordinal: 1, physical: point(0, 0), score: 5),
                shot("shot-c", stringID: stringID("string-c"), ordinal: 1, physical: point(0, 0), score: nil)
            ]
        )

        let mixed = SessionAnalyticsEngine().analytics(for: store)
        let targetAOnly = SessionAnalyticsEngine().analytics(
            for: store,
            filter: AnalyticsFilter(targetDefinitionID: targetA)
        )

        XCTAssertNil(mixed.summary.averageScorePerString)
        XCTAssertTrue(mixed.scoreTrend.isEmpty)
        XCTAssertEqual(try XCTUnwrap(targetAOnly.summary.averageScorePerString), 10, accuracy: 0.0001)
        XCTAssertEqual(targetAOnly.scoreTrend.count, 1)
    }

    func testEmptyFilterResultIsStructuredAndNonNumericMetricsAreUnavailable() throws {
        let store = try makeStore(
            sessions: [session("session-1", startedAt: try date("2026-08-01T10:00:00Z"), firearmID: firearmA, distance: 7, targetID: targetA)],
            strings: [],
            shots: []
        )

        let result = SessionAnalyticsEngine().analytics(
            for: store,
            filter: AnalyticsFilter(firearmID: firearmB)
        )

        XCTAssertEqual(result.summary.sessionCount, 0)
        XCTAssertEqual(result.summary.stringCount, 0)
        XCTAssertEqual(result.summary.acceptedShotCount, 0)
        XCTAssertNil(result.summary.averageGroupSize)
        XCTAssertNil(result.summary.averageScorePerString)
        XCTAssertTrue(result.historyItems.isEmpty)
    }

    func testTrendIsChronologicalAndHistoryIsReverseChronological() throws {
        let store = try makeStore(
            sessions: [
                session("later", startedAt: try date("2026-08-03T10:00:00Z"), firearmID: firearmA, distance: 7, targetID: targetA),
                session("earlier", startedAt: try date("2026-08-01T10:00:00Z"), firearmID: firearmA, distance: 7, targetID: targetA)
            ],
            strings: [
                string("later-string", sessionID: sessionID("later"), index: 1, startedAt: try date("2026-08-03T10:01:00Z")),
                string("earlier-string", sessionID: sessionID("earlier"), index: 1, startedAt: try date("2026-08-01T10:01:00Z"))
            ],
            shots: [
                shot("later-1", stringID: stringID("later-string"), ordinal: 1, physical: point(0, 0), score: nil),
                shot("later-2", stringID: stringID("later-string"), ordinal: 2, physical: point(1, 0), score: nil),
                shot("earlier-1", stringID: stringID("earlier-string"), ordinal: 1, physical: point(0, 0), score: nil),
                shot("earlier-2", stringID: stringID("earlier-string"), ordinal: 2, physical: point(1, 0), score: nil)
            ]
        )

        let result = SessionAnalyticsEngine().analytics(for: store)

        XCTAssertEqual(result.groupSizeTrend.map(\.id), [stringID("earlier-string"), stringID("later-string")])
        XCTAssertEqual(result.historyItems.map(\.id), [sessionID("later"), sessionID("earlier")])
    }

    func testSingleQualifyingPointDoesNotClaimTrendClassification() throws {
        let store = try makeStore(
            sessions: [session("session-1", startedAt: try date("2026-08-01T10:00:00Z"), firearmID: firearmA, distance: 7, targetID: targetA)],
            strings: [string("string-1", sessionID: sessionID("session-1"), index: 1, startedAt: try date("2026-08-01T10:01:00Z"))],
            shots: [
                shot("shot-1", stringID: stringID("string-1"), ordinal: 1, physical: point(0, 0), score: nil),
                shot("shot-2", stringID: stringID("string-1"), ordinal: 2, physical: point(1, 0), score: nil)
            ]
        )

        let result = SessionAnalyticsEngine().analytics(for: store)

        XCTAssertEqual(result.summary.sessionCount, 1)
        XCTAssertEqual(try XCTUnwrap(result.summary.averageGroupSize), 1, accuracy: 0.0001)
        XCTAssertTrue(result.summary.needsMoreDataForTrendClassification)
    }

    private let firearmA = FirearmProfileID(rawValue: "firearm-a")
    private let firearmB = FirearmProfileID(rawValue: "firearm-b")
    private let targetA = SupportedTargetCatalog.bullseyePracticeID
    private let targetB = TargetDefinitionID(rawValue: "target-b")

    private func makeStore(
        sessions: [RangeSession],
        strings: [RangeString],
        shots: [Shot],
        impactCorrectionHistory: [AcceptedImpact] = []
    ) throws -> PersistedRangeSightStore {
        PersistedRangeSightStore(
            firearmProfiles: [
                FirearmProfile(
                    id: firearmA,
                    nickname: "Firearm A",
                    category: .handgun,
                    caliber: "9mm",
                    notes: nil,
                    createdAt: try date("2026-01-01T00:00:00Z")
                ),
                FirearmProfile(
                    id: firearmB,
                    nickname: "Firearm B",
                    category: .handgun,
                    caliber: nil,
                    notes: nil,
                    createdAt: try date("2026-01-01T00:00:00Z")
                )
            ],
            targetDefinitions: [
                SupportedTargetCatalog.bullseyePracticeTargetDefinition,
                TargetDefinition(
                    id: targetB,
                    name: "Incompatible Target",
                    revision: 1,
                    physicalDimensions: try PhysicalDimensions(width: 8, height: 8, unit: .inch),
                    scoringZones: [],
                    aimPoints: [],
                    supportedModes: [.genericImpact]
                )
            ],
            rangeSessions: sessions,
            rangeStrings: strings,
            shots: shots,
            impactCorrectionHistory: impactCorrectionHistory
        )
    }

    private func session(
        _ rawID: String,
        startedAt: Date,
        firearmID: FirearmProfileID?,
        distance: Double,
        targetID: TargetDefinitionID
    ) throws -> RangeSession {
        RangeSession(
            id: sessionID(rawID),
            startedAt: startedAt,
            endedAt: nil,
            distance: distance,
            distanceUnit: .yard,
            firearmID: firearmID,
            targetDefinitionID: targetID,
            device: DeviceMetadata(platform: .iOS, modelName: "iPhone", osVersion: "18.0", appVersion: "0.1.0")
        )
    }

    private func string(
        _ rawID: String,
        sessionID: RangeSessionID,
        index: Int,
        startedAt: Date
    ) throws -> RangeString {
        RangeString(
            id: stringID(rawID),
            sessionID: sessionID,
            index: index,
            baselineAssetID: nil,
            startedAt: startedAt,
            endedAt: nil
        )
    }

    private func shot(
        _ rawID: String,
        stringID: RangeStringID,
        ordinal: Int,
        physical: PhysicalPoint,
        score: Double?
    ) throws -> Shot {
        try shot(
            rawID,
            stringID: stringID,
            ordinal: ordinal,
            normalized: normalized(0.5, 0.5),
            physical: physical,
            score: score
        )
    }

    private func shot(
        _ rawID: String,
        stringID: RangeStringID,
        ordinal: Int,
        normalized: NormalizedTargetCoordinate,
        physical: PhysicalPoint? = nil,
        score: Double?
    ) throws -> Shot {
        try Shot(
            id: shotID(rawID),
            stringID: stringID,
            ordinal: ordinal,
            timestamp: try date("2026-08-01T10:00:00Z").addingTimeInterval(Double(ordinal)),
            normalized: normalized,
            physical: physical,
            confidence: 0.9,
            source: .autoConfirmed,
            corrected: false,
            score: score.map { ShotScore(value: $0, targetDefinitionRevision: 1, reviewable: false) }
        )
    }

    private func point(_ x: Double, _ y: Double) -> PhysicalPoint {
        PhysicalPoint(x: x, y: y, unit: .inch)
    }

    private func normalized(_ x: Double, _ y: Double) throws -> NormalizedTargetCoordinate {
        try NormalizedTargetCoordinate(x: x, y: y)
    }

    private func date(_ text: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: text))
    }

    private func sessionID(_ rawValue: String) -> RangeSessionID {
        RangeSessionID(rawValue: rawValue)
    }

    private func stringID(_ rawValue: String) -> RangeStringID {
        RangeStringID(rawValue: rawValue)
    }

    private func shotID(_ rawValue: String) -> ShotID {
        ShotID(rawValue: rawValue)
    }
}
