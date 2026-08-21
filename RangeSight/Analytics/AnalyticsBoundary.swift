import Foundation

public protocol AnalyticsRecorder: Sendable {}

public enum AnalyticsDateRange: Codable, Equatable, Sendable {
    case allTime
    case last30Days(referenceDate: Date)
    case last90Days(referenceDate: Date)
    case custom(start: Date?, end: Date?)

    public func contains(_ date: Date) -> Bool {
        switch self {
        case .allTime:
            return true
        case .last30Days(let referenceDate):
            return date >= referenceDate.addingTimeInterval(-30 * 24 * 60 * 60) && date <= referenceDate
        case .last90Days(let referenceDate):
            return date >= referenceDate.addingTimeInterval(-90 * 24 * 60 * 60) && date <= referenceDate
        case .custom(let start, let end):
            if let start, date < start {
                return false
            }

            if let end, date >= end {
                return false
            }

            return true
        }
    }
}

public struct AnalyticsFilter: Codable, Equatable, Sendable {
    public let firearmID: FirearmProfileID?
    public let distance: Double?
    public let distanceUnit: DistanceUnit?
    public let targetDefinitionID: TargetDefinitionID?
    public let dateRange: AnalyticsDateRange

    public init(
        firearmID: FirearmProfileID? = nil,
        distance: Double? = nil,
        distanceUnit: DistanceUnit? = nil,
        targetDefinitionID: TargetDefinitionID? = nil,
        dateRange: AnalyticsDateRange = .allTime
    ) {
        self.firearmID = firearmID
        self.distance = distance
        self.distanceUnit = distanceUnit
        self.targetDefinitionID = targetDefinitionID
        self.dateRange = dateRange
    }

    public func matches(_ session: RangeSession) -> Bool {
        if let firearmID, session.firearmID != firearmID {
            return false
        }

        if let distance, session.distance != distance {
            return false
        }

        if let distanceUnit, session.distanceUnit != distanceUnit {
            return false
        }

        if let targetDefinitionID, session.targetDefinitionID != targetDefinitionID {
            return false
        }

        return dateRange.contains(session.startedAt)
    }
}

public struct AnalyticsMetricRecord: Codable, Equatable, Sendable {
    public let sessionID: RangeSessionID
    public let stringID: RangeStringID
    public let date: Date
    public let value: Double
    public let unit: LengthUnit?
    public let firearmID: FirearmProfileID?
    public let distance: Double
    public let distanceUnit: DistanceUnit
    public let targetDefinitionID: TargetDefinitionID

    public init(
        sessionID: RangeSessionID,
        stringID: RangeStringID,
        date: Date,
        value: Double,
        unit: LengthUnit?,
        firearmID: FirearmProfileID?,
        distance: Double,
        distanceUnit: DistanceUnit,
        targetDefinitionID: TargetDefinitionID
    ) {
        self.sessionID = sessionID
        self.stringID = stringID
        self.date = date
        self.value = value
        self.unit = unit
        self.firearmID = firearmID
        self.distance = distance
        self.distanceUnit = distanceUnit
        self.targetDefinitionID = targetDefinitionID
    }
}

public struct PerformanceTrendPoint: Codable, Equatable, Sendable, Identifiable {
    public let id: RangeStringID
    public let sessionID: RangeSessionID
    public let date: Date
    public let stringIndex: Int
    public let firearmID: FirearmProfileID?
    public let distance: Double
    public let distanceUnit: DistanceUnit
    public let targetDefinitionID: TargetDefinitionID
    public let acceptedShotCount: Int
    public let groupMetrics: GroupMetrics?
    public let totalScore: Double?
    public let scoredShotCount: Int

    public init(
        id: RangeStringID,
        sessionID: RangeSessionID,
        date: Date,
        stringIndex: Int,
        firearmID: FirearmProfileID?,
        distance: Double,
        distanceUnit: DistanceUnit,
        targetDefinitionID: TargetDefinitionID,
        acceptedShotCount: Int,
        groupMetrics: GroupMetrics?,
        totalScore: Double?,
        scoredShotCount: Int
    ) {
        self.id = id
        self.sessionID = sessionID
        self.date = date
        self.stringIndex = stringIndex
        self.firearmID = firearmID
        self.distance = distance
        self.distanceUnit = distanceUnit
        self.targetDefinitionID = targetDefinitionID
        self.acceptedShotCount = acceptedShotCount
        self.groupMetrics = groupMetrics
        self.totalScore = totalScore
        self.scoredShotCount = scoredShotCount
    }
}

public struct SessionHistoryItem: Codable, Equatable, Sendable, Identifiable {
    public let id: RangeSessionID
    public let startedAt: Date
    public let endedAt: Date?
    public let firearmID: FirearmProfileID?
    public let firearmName: String?
    public let distance: Double
    public let distanceUnit: DistanceUnit
    public let targetDefinitionID: TargetDefinitionID
    public let targetName: String?
    public let stringCount: Int
    public let acceptedShotCount: Int
    public let bestGroupSize: Double?
    public let groupUnit: LengthUnit?
    public let totalScore: Double?

    public init(
        id: RangeSessionID,
        startedAt: Date,
        endedAt: Date?,
        firearmID: FirearmProfileID?,
        firearmName: String?,
        distance: Double,
        distanceUnit: DistanceUnit,
        targetDefinitionID: TargetDefinitionID,
        targetName: String?,
        stringCount: Int,
        acceptedShotCount: Int,
        bestGroupSize: Double?,
        groupUnit: LengthUnit?,
        totalScore: Double?
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.firearmID = firearmID
        self.firearmName = firearmName
        self.distance = distance
        self.distanceUnit = distanceUnit
        self.targetDefinitionID = targetDefinitionID
        self.targetName = targetName
        self.stringCount = stringCount
        self.acceptedShotCount = acceptedShotCount
        self.bestGroupSize = bestGroupSize
        self.groupUnit = groupUnit
        self.totalScore = totalScore
    }
}

public struct DetectorValidationSummary: Codable, Equatable, Sendable {
    public let autoConfirmedCount: Int
    public let userConfirmedCandidateCount: Int
    public let userAddedCount: Int
    public let userMovedCount: Int
    public let userDeletedCount: Int

    public init(
        autoConfirmedCount: Int = 0,
        userConfirmedCandidateCount: Int = 0,
        userAddedCount: Int = 0,
        userMovedCount: Int = 0,
        userDeletedCount: Int = 0
    ) {
        self.autoConfirmedCount = autoConfirmedCount
        self.userConfirmedCandidateCount = userConfirmedCandidateCount
        self.userAddedCount = userAddedCount
        self.userMovedCount = userMovedCount
        self.userDeletedCount = userDeletedCount
    }

    public var totalCorrectionEvents: Int {
        autoConfirmedCount + userConfirmedCandidateCount + userAddedCount + userMovedCount + userDeletedCount
    }
}

public struct AnalyticsSummary: Codable, Equatable, Sendable {
    public let sessionCount: Int
    public let stringCount: Int
    public let acceptedShotCount: Int
    public let averageGroupSize: Double?
    public let medianGroupSize: Double?
    public let bestGroup: AnalyticsMetricRecord?
    public let averageScorePerString: Double?
    public let bestScore: AnalyticsMetricRecord?
    public let scoreTargetDefinitionID: TargetDefinitionID?
    public let averagePointOfImpactOffset: PhysicalPoint?
    public let averageHorizontalDispersion: Double?
    public let averageVerticalDispersion: Double?
    public let metricUnit: LengthUnit?
    public let needsMoreDataForTrendClassification: Bool

    public init(
        sessionCount: Int,
        stringCount: Int,
        acceptedShotCount: Int,
        averageGroupSize: Double?,
        medianGroupSize: Double?,
        bestGroup: AnalyticsMetricRecord?,
        averageScorePerString: Double?,
        bestScore: AnalyticsMetricRecord?,
        scoreTargetDefinitionID: TargetDefinitionID?,
        averagePointOfImpactOffset: PhysicalPoint?,
        averageHorizontalDispersion: Double?,
        averageVerticalDispersion: Double?,
        metricUnit: LengthUnit?,
        needsMoreDataForTrendClassification: Bool
    ) {
        self.sessionCount = sessionCount
        self.stringCount = stringCount
        self.acceptedShotCount = acceptedShotCount
        self.averageGroupSize = averageGroupSize
        self.medianGroupSize = medianGroupSize
        self.bestGroup = bestGroup
        self.averageScorePerString = averageScorePerString
        self.bestScore = bestScore
        self.scoreTargetDefinitionID = scoreTargetDefinitionID
        self.averagePointOfImpactOffset = averagePointOfImpactOffset
        self.averageHorizontalDispersion = averageHorizontalDispersion
        self.averageVerticalDispersion = averageVerticalDispersion
        self.metricUnit = metricUnit
        self.needsMoreDataForTrendClassification = needsMoreDataForTrendClassification
    }
}

public struct HistoryAnalyticsResult: Codable, Equatable, Sendable {
    public let filter: AnalyticsFilter
    public let summary: AnalyticsSummary
    public let groupSizeTrend: [PerformanceTrendPoint]
    public let scoreTrend: [PerformanceTrendPoint]
    public let pointOfImpactTrend: [PerformanceTrendPoint]
    public let historyItems: [SessionHistoryItem]
    public let detectorValidation: DetectorValidationSummary

    public init(
        filter: AnalyticsFilter,
        summary: AnalyticsSummary,
        groupSizeTrend: [PerformanceTrendPoint],
        scoreTrend: [PerformanceTrendPoint],
        pointOfImpactTrend: [PerformanceTrendPoint],
        historyItems: [SessionHistoryItem],
        detectorValidation: DetectorValidationSummary
    ) {
        self.filter = filter
        self.summary = summary
        self.groupSizeTrend = groupSizeTrend
        self.scoreTrend = scoreTrend
        self.pointOfImpactTrend = pointOfImpactTrend
        self.historyItems = historyItems
        self.detectorValidation = detectorValidation
    }
}

public struct SessionAnalyticsEngine: Sendable {
    public init() {}

    public func analytics(
        for store: PersistedRangeSightStore,
        filter: AnalyticsFilter = AnalyticsFilter()
    ) -> HistoryAnalyticsResult {
        let firearmByID = Dictionary(uniqueKeysWithValues: store.firearmProfiles.map { ($0.id, $0) })
        let targetByID = Dictionary(uniqueKeysWithValues: store.targetDefinitions.map { ($0.id, $0) })
        let stringsBySessionID = Dictionary(grouping: store.rangeStrings, by: \.sessionID)
        let shotsByStringID = Dictionary(grouping: store.shots, by: \.stringID)
        let impactsByStringID = Dictionary(grouping: store.impactCorrectionHistory, by: \.stringID)

        let sessions = store.rangeSessions
            .filter { filter.matches($0) }
            .sorted(by: chronologicalSessionSort)

        var trendPoints: [PerformanceTrendPoint] = []
        var historyItems: [SessionHistoryItem] = []
        var includedStringIDs: Set<RangeStringID> = []

        for session in sessions {
            let sessionStrings = (stringsBySessionID[session.id] ?? [])
                .sorted(by: stringSort)
            var sessionShotCount = 0
            var sessionScores: [Double] = []
            var sessionGroupSizes: [Double] = []
            var sessionGroupUnit: LengthUnit?

            for rangeString in sessionStrings {
                includedStringIDs.insert(rangeString.id)
                let shots = (shotsByStringID[rangeString.id] ?? [])
                    .sorted(by: shotSort)
                let points = physicalPoints(
                    for: shots,
                    targetDefinition: targetByID[session.targetDefinitionID]
                )
                let groupMetrics = makeGroupMetrics(from: points)
                let scoreValues = shots.compactMap(\.score?.value)
                let totalScore = scoreValues.isEmpty ? nil : scoreValues.reduce(0, +)

                sessionShotCount += shots.count
                if let totalScore {
                    sessionScores.append(totalScore)
                }
                if let groupMetrics {
                    sessionGroupSizes.append(groupMetrics.extremeSpread)
                    sessionGroupUnit = groupMetrics.groupCenter.unit
                }

                trendPoints.append(
                    PerformanceTrendPoint(
                        id: rangeString.id,
                        sessionID: session.id,
                        date: rangeString.startedAt,
                        stringIndex: rangeString.index,
                        firearmID: session.firearmID,
                        distance: session.distance,
                        distanceUnit: session.distanceUnit,
                        targetDefinitionID: session.targetDefinitionID,
                        acceptedShotCount: shots.count,
                        groupMetrics: groupMetrics,
                        totalScore: totalScore,
                        scoredShotCount: scoreValues.count
                    )
                )
            }

            historyItems.append(
                SessionHistoryItem(
                    id: session.id,
                    startedAt: session.startedAt,
                    endedAt: session.endedAt,
                    firearmID: session.firearmID,
                    firearmName: session.firearmID.flatMap { firearmByID[$0]?.nickname },
                    distance: session.distance,
                    distanceUnit: session.distanceUnit,
                    targetDefinitionID: session.targetDefinitionID,
                    targetName: targetByID[session.targetDefinitionID]?.name,
                    stringCount: sessionStrings.count,
                    acceptedShotCount: sessionShotCount,
                    bestGroupSize: sessionGroupSizes.min(),
                    groupUnit: sessionGroupUnit,
                    totalScore: sessionScores.isEmpty ? nil : sessionScores.reduce(0, +)
                )
            )
        }

        trendPoints.sort(by: trendSort)
        historyItems.sort(by: reverseChronologicalHistorySort)

        let detectorValidation = detectorSummary(
            for: includedStringIDs,
            impactsByStringID: impactsByStringID
        )
        let summary = makeSummary(
            sessions: sessions,
            trendPoints: trendPoints
        )

        return HistoryAnalyticsResult(
            filter: filter,
            summary: summary,
            groupSizeTrend: trendPoints.filter { $0.groupMetrics != nil },
            scoreTrend: comparableScoreTrend(from: trendPoints),
            pointOfImpactTrend: trendPoints.filter { $0.groupMetrics != nil },
            historyItems: historyItems,
            detectorValidation: detectorValidation
        )
    }

    private func makeSummary(
        sessions: [RangeSession],
        trendPoints: [PerformanceTrendPoint]
    ) -> AnalyticsSummary {
        let groupPoints = trendPoints.compactMap { point -> (PerformanceTrendPoint, GroupMetrics)? in
            guard let metrics = point.groupMetrics else {
                return nil
            }

            return (point, metrics)
        }
        let groupSizes = groupPoints.map { $0.1.extremeSpread }
        let metricUnit = commonUnit(groupPoints.map { $0.1.groupCenter.unit })
        let comparableGroupPoints = metricUnit == nil ? [] : groupPoints
        let scorePoints = comparableScoreTrend(from: trendPoints)
        let scoreValues = scorePoints.compactMap(\.totalScore)
        let scoreTargetIDs = Set(scorePoints.map(\.targetDefinitionID))

        return AnalyticsSummary(
            sessionCount: sessions.count,
            stringCount: trendPoints.count,
            acceptedShotCount: trendPoints.map(\.acceptedShotCount).reduce(0, +),
            averageGroupSize: metricUnit == nil ? nil : average(groupSizes),
            medianGroupSize: metricUnit == nil ? nil : median(groupSizes),
            bestGroup: comparableGroupPoints
                .min { $0.1.extremeSpread < $1.1.extremeSpread }
                .map { record(for: $0.0, value: $0.1.extremeSpread, unit: $0.1.groupCenter.unit) },
            averageScorePerString: scoreValues.isEmpty ? nil : average(scoreValues),
            bestScore: scorePoints
                .compactMap { point -> AnalyticsMetricRecord? in
                    guard let totalScore = point.totalScore else {
                        return nil
                    }

                    return record(for: point, value: totalScore, unit: nil)
                }
                .max { $0.value < $1.value },
            scoreTargetDefinitionID: scoreTargetIDs.count == 1 ? scoreTargetIDs.first : nil,
            averagePointOfImpactOffset: averagePointOfImpactOffset(for: comparableGroupPoints.map { $0.1 }),
            averageHorizontalDispersion: metricUnit == nil ? nil : average(comparableGroupPoints.map { $0.1.horizontalStandardDeviation }),
            averageVerticalDispersion: metricUnit == nil ? nil : average(comparableGroupPoints.map { $0.1.verticalStandardDeviation }),
            metricUnit: metricUnit,
            needsMoreDataForTrendClassification: groupPoints.count < 2 && scorePoints.count < 2
        )
    }

    private func physicalPoints(
        for shots: [Shot],
        targetDefinition: TargetDefinition?
    ) -> [PhysicalPoint] {
        shots.compactMap { shot in
            if let physical = shot.physical {
                return physical
            }

            guard let dimensions = targetDefinition?.physicalDimensions else {
                return nil
            }

            return TargetCoordinateConverter.physicalPoint(from: shot.normalized, dimensions: dimensions)
        }
    }

    private func makeGroupMetrics(from points: [PhysicalPoint]) -> GroupMetrics? {
        guard points.count >= 2,
              let aimPoint = points.first.map({ PhysicalPoint(x: 0, y: 0, unit: $0.unit) }) else {
            return nil
        }

        return try? GroupMetricCalculator.metrics(for: points, aimPoint: aimPoint)
    }

    private func detectorSummary(
        for stringIDs: Set<RangeStringID>,
        impactsByStringID: [RangeStringID: [AcceptedImpact]]
    ) -> DetectorValidationSummary {
        let impacts = stringIDs.flatMap { impactsByStringID[$0] ?? [] }
        let counters = ImpactCorrectionState.counters(for: impacts)
        return DetectorValidationSummary(
            autoConfirmedCount: counters.autoConfirmedCount,
            userConfirmedCandidateCount: counters.userConfirmedCandidateCount,
            userAddedCount: counters.userAddedCount,
            userMovedCount: counters.userMovedCount,
            userDeletedCount: counters.userDeletedCount
        )
    }

    private func comparableScoreTrend(from trendPoints: [PerformanceTrendPoint]) -> [PerformanceTrendPoint] {
        let scoredPoints = trendPoints.filter { $0.totalScore != nil }
        let targetIDs = Set(scoredPoints.map(\.targetDefinitionID))
        guard targetIDs.count <= 1 else {
            return []
        }

        return scoredPoints
    }

    private func averagePointOfImpactOffset(for metrics: [GroupMetrics]) -> PhysicalPoint? {
        guard let unit = metrics.first?.pointOfImpactOffset.unit,
              metrics.allSatisfy({ $0.pointOfImpactOffset.unit == unit }) else {
            return nil
        }

        return PhysicalPoint(
            x: average(metrics.map(\.pointOfImpactOffset.x)) ?? 0,
            y: average(metrics.map(\.pointOfImpactOffset.y)) ?? 0,
            unit: unit
        )
    }

    private func commonUnit(_ units: [LengthUnit]) -> LengthUnit? {
        guard let first = units.first,
              units.allSatisfy({ $0 == first }) else {
            return nil
        }

        return first
    }

    private func record(
        for point: PerformanceTrendPoint,
        value: Double,
        unit: LengthUnit?
    ) -> AnalyticsMetricRecord {
        AnalyticsMetricRecord(
            sessionID: point.sessionID,
            stringID: point.id,
            date: point.date,
            value: value,
            unit: unit,
            firearmID: point.firearmID,
            distance: point.distance,
            distanceUnit: point.distanceUnit,
            targetDefinitionID: point.targetDefinitionID
        )
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else {
            return nil
        }

        return values.reduce(0, +) / Double(values.count)
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else {
            return nil
        }

        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }

        return sorted[middle]
    }

    private func chronologicalSessionSort(_ lhs: RangeSession, _ rhs: RangeSession) -> Bool {
        if lhs.startedAt == rhs.startedAt {
            return lhs.id.rawValue < rhs.id.rawValue
        }

        return lhs.startedAt < rhs.startedAt
    }

    private func reverseChronologicalHistorySort(_ lhs: SessionHistoryItem, _ rhs: SessionHistoryItem) -> Bool {
        if lhs.startedAt == rhs.startedAt {
            return lhs.id.rawValue > rhs.id.rawValue
        }

        return lhs.startedAt > rhs.startedAt
    }

    private func stringSort(_ lhs: RangeString, _ rhs: RangeString) -> Bool {
        if lhs.index == rhs.index {
            return lhs.id.rawValue < rhs.id.rawValue
        }

        return lhs.index < rhs.index
    }

    private func shotSort(_ lhs: Shot, _ rhs: Shot) -> Bool {
        if lhs.ordinal == rhs.ordinal {
            return lhs.id.rawValue < rhs.id.rawValue
        }

        return lhs.ordinal < rhs.ordinal
    }

    private func trendSort(_ lhs: PerformanceTrendPoint, _ rhs: PerformanceTrendPoint) -> Bool {
        if lhs.date == rhs.date {
            if lhs.sessionID == rhs.sessionID {
                if lhs.stringIndex == rhs.stringIndex {
                    return lhs.id.rawValue < rhs.id.rawValue
                }

                return lhs.stringIndex < rhs.stringIndex
            }

            return lhs.sessionID.rawValue < rhs.sessionID.rawValue
        }

        return lhs.date < rhs.date
    }
}

public struct SessionAnalyticsRepositoryService: Sendable {
    private let engine: SessionAnalyticsEngine

    public init(engine: SessionAnalyticsEngine = SessionAnalyticsEngine()) {
        self.engine = engine
    }

    public func analytics(
        repository: any RangeSightRepository,
        filter: AnalyticsFilter = AnalyticsFilter()
    ) async throws -> HistoryAnalyticsResult {
        let store = try await repository.loadStore()
        return engine.analytics(for: store, filter: filter)
    }
}
