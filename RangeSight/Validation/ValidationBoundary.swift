import Foundation

public enum RangeValidationSchema {
    public static let currentVersion = 1
}

public struct RangeValidationConfiguration: Codable, Equatable, Sendable {
    public let coordinateTolerance: Double
    public let maximumConfirmationLatency: TimeInterval?

    public init(
        coordinateTolerance: Double = 0.035,
        maximumConfirmationLatency: TimeInterval? = nil
    ) throws {
        guard coordinateTolerance > 0,
              coordinateTolerance.isFinite else {
            throw RangeValidationError.invalidConfiguration
        }

        if let maximumConfirmationLatency {
            guard maximumConfirmationLatency >= 0,
                  maximumConfirmationLatency.isFinite else {
                throw RangeValidationError.invalidConfiguration
            }
        }

        self.coordinateTolerance = coordinateTolerance
        self.maximumConfirmationLatency = maximumConfirmationLatency
    }

    public static let `default` = RangeValidationConfiguration(
        coordinateTolerance: 0.035,
        maximumConfirmationLatency: nil,
        validated: ()
    )

    private init(coordinateTolerance: Double, maximumConfirmationLatency: TimeInterval?, validated: Void) {
        self.coordinateTolerance = coordinateTolerance
        self.maximumConfirmationLatency = maximumConfirmationLatency
    }
}

public struct RangeValidationContext: Codable, Equatable, Sendable {
    public let deviceModel: String?
    public let testCondition: String?
    public let appVersion: String?
    public let detectorVersion: String?
    public let metadata: [String: String]

    public init(
        deviceModel: String? = nil,
        testCondition: String? = nil,
        appVersion: String? = nil,
        detectorVersion: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.deviceModel = deviceModel
        self.testCondition = testCondition
        self.appVersion = appVersion
        self.detectorVersion = detectorVersion
        self.metadata = metadata
    }
}

public struct RangeValidationGroundTruthImpact: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let timestamp: TimeInterval
    public let coordinate: NormalizedImagePoint
    public let notes: String?

    public init(id: String, timestamp: TimeInterval, coordinate: NormalizedImagePoint, notes: String? = nil) throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              timestamp >= 0,
              timestamp.isFinite else {
            throw RangeValidationError.invalidGroundTruth
        }

        self.id = id
        self.timestamp = timestamp
        self.coordinate = coordinate
        self.notes = notes
    }

    public init(expectedEvent: ReplayExpectedEvent) throws {
        guard expectedEvent.kind == .shot,
              let impact = expectedEvent.normalizedImpact else {
            throw RangeValidationError.invalidGroundTruth
        }

        try self.init(
            id: expectedEvent.id,
            timestamp: expectedEvent.timestamp,
            coordinate: try NormalizedImagePoint(x: impact.x, y: impact.y),
            notes: expectedEvent.notes
        )
    }
}

public struct RangeValidationDetectedImpact: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let frameSequenceIndex: Int
    public let timestamp: TimeInterval
    public let coordinate: NormalizedImagePoint
    public let confidence: Double
    public let confidenceBand: TemporalConfidenceBand?
    public let sourceEventID: String?
    public let audioAssisted: Bool

    public init(
        id: String,
        frameSequenceIndex: Int,
        timestamp: TimeInterval,
        coordinate: NormalizedImagePoint,
        confidence: Double,
        confidenceBand: TemporalConfidenceBand? = nil,
        sourceEventID: String? = nil,
        audioAssisted: Bool = false
    ) throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              frameSequenceIndex >= 0,
              timestamp >= 0,
              timestamp.isFinite,
              (0...1).contains(confidence) else {
            throw RangeValidationError.invalidDetection
        }

        self.id = id
        self.frameSequenceIndex = frameSequenceIndex
        self.timestamp = timestamp
        self.coordinate = coordinate
        self.confidence = confidence
        self.confidenceBand = confidenceBand
        self.sourceEventID = sourceEventID
        self.audioAssisted = audioAssisted
    }

    public init(liveImpactEvent: LiveImpactEvent) throws {
        try self.init(
            id: liveImpactEvent.id,
            frameSequenceIndex: liveImpactEvent.frameSequenceIndex,
            timestamp: liveImpactEvent.timestamp,
            coordinate: liveImpactEvent.normalizedCoordinate,
            confidence: liveImpactEvent.confidence,
            confidenceBand: liveImpactEvent.confidenceBand,
            sourceEventID: liveImpactEvent.temporalCandidateID,
            audioAssisted: liveImpactEvent.audioAssisted
        )
    }
}

public enum RangeValidationMatchStatus: String, Codable, Equatable, Sendable {
    case detected
    case missed
    case falsePositive
}

public struct RangeValidationMatch: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let status: RangeValidationMatchStatus
    public let groundTruth: RangeValidationGroundTruthImpact?
    public let detection: RangeValidationDetectedImpact?
    public let coordinateError: Double?
    public let confirmationLatency: TimeInterval?

    public init(
        id: String,
        status: RangeValidationMatchStatus,
        groundTruth: RangeValidationGroundTruthImpact?,
        detection: RangeValidationDetectedImpact?,
        coordinateError: Double?,
        confirmationLatency: TimeInterval?
    ) throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RangeValidationError.invalidMatch
        }

        switch status {
        case .detected:
            guard groundTruth != nil, detection != nil, coordinateError != nil, confirmationLatency != nil else {
                throw RangeValidationError.invalidMatch
            }
        case .missed:
            guard groundTruth != nil, detection == nil, coordinateError == nil, confirmationLatency == nil else {
                throw RangeValidationError.invalidMatch
            }
        case .falsePositive:
            guard groundTruth == nil, detection != nil, coordinateError == nil, confirmationLatency == nil else {
                throw RangeValidationError.invalidMatch
            }
        }

        self.id = id
        self.status = status
        self.groundTruth = groundTruth
        self.detection = detection
        self.coordinateError = coordinateError
        self.confirmationLatency = confirmationLatency
    }
}

public struct RangeValidationMetrics: Codable, Equatable, Sendable {
    public let expectedImpactCount: Int
    public let detectedImpactCount: Int
    public let truePositiveCount: Int
    public let missedImpactCount: Int
    public let falsePositiveCount: Int
    public let precision: Double?
    public let recall: Double?
    public let meanCoordinateError: Double?
    public let maximumCoordinateError: Double?
    public let meanConfirmationLatency: TimeInterval?
    public let maximumConfirmationLatency: TimeInterval?

    public init(matches: [RangeValidationMatch]) {
        expectedImpactCount = matches.filter { $0.groundTruth != nil }.count
        detectedImpactCount = matches.filter { $0.detection != nil }.count
        truePositiveCount = matches.filter { $0.status == .detected }.count
        missedImpactCount = matches.filter { $0.status == .missed }.count
        falsePositiveCount = matches.filter { $0.status == .falsePositive }.count

        precision = detectedImpactCount > 0 ? Double(truePositiveCount) / Double(detectedImpactCount) : nil
        recall = expectedImpactCount > 0 ? Double(truePositiveCount) / Double(expectedImpactCount) : nil

        let coordinateErrors = matches.compactMap(\.coordinateError)
        meanCoordinateError = Self.mean(coordinateErrors)
        maximumCoordinateError = coordinateErrors.max()

        let latencies = matches.compactMap(\.confirmationLatency)
        meanConfirmationLatency = Self.mean(latencies)
        maximumConfirmationLatency = latencies.max()
    }

    private static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

public struct RangeValidationDiagnosticAggregate: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let key: String
    public let count: Int
    public let minimum: Double
    public let maximum: Double
    public let average: Double

    public init(key: String, values: [Double]) throws {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let minimum = values.min(),
              let maximum = values.max() else {
            throw RangeValidationError.invalidDiagnostics
        }

        self.id = key
        self.key = key
        self.count = values.count
        self.minimum = minimum
        self.maximum = maximum
        self.average = values.reduce(0, +) / Double(values.count)
    }
}

public struct RangeValidationStageCount: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let stage: VisionPipelineStage
    public let count: Int

    public init(stage: VisionPipelineStage, count: Int) throws {
        guard count >= 0 else {
            throw RangeValidationError.invalidDiagnostics
        }

        self.id = stage.rawValue
        self.stage = stage
        self.count = count
    }
}

public struct RangeValidationConfidenceBandCount: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let band: TemporalConfidenceBand
    public let count: Int

    public init(band: TemporalConfidenceBand, count: Int) throws {
        guard count >= 0 else {
            throw RangeValidationError.invalidDiagnostics
        }

        self.id = band.rawValue
        self.band = band
        self.count = count
    }
}

public struct RangeValidationDiagnosticsSummary: Codable, Equatable, Sendable {
    public let processedFrameCount: Int
    public let pipelineEventCount: Int
    public let stageCounts: [RangeValidationStageCount]
    public let diagnosticAggregates: [RangeValidationDiagnosticAggregate]
    public let registrationFailureEventCount: Int
    public let globalChangeRejectedEventCount: Int
    public let cadenceDroppedFrameCount: Int
    public let backpressureDroppedFrameCount: Int
    public let invalidROIFrameCount: Int
    public let confidenceBandCounts: [RangeValidationConfidenceBandCount]

    public init(
        processedFrameCount: Int,
        events: [VisionPipelineEvent],
        detections: [RangeValidationDetectedImpact]
    ) throws {
        guard processedFrameCount >= 0 else {
            throw RangeValidationError.invalidDiagnostics
        }

        self.processedFrameCount = processedFrameCount
        pipelineEventCount = events.count
        stageCounts = try VisionPipelineStage.allCases.compactMap { stage in
            let count = events.filter { $0.stage == stage }.count
            return count > 0 ? try RangeValidationStageCount(stage: stage, count: count) : nil
        }

        var valuesByKey: [String: [Double]] = [:]
        for diagnostic in events.flatMap(\.diagnostics) {
            valuesByKey[diagnostic.key, default: []].append(diagnostic.value)
        }

        diagnosticAggregates = try valuesByKey
            .keys
            .sorted()
            .map { key in
                try RangeValidationDiagnosticAggregate(key: key, values: valuesByKey[key] ?? [])
            }

        let registeredStatus = FrameRegistrationDiagnostics.statusCodeForDiagnostics(.registered)
        let referenceReadyStatus = FrameRegistrationDiagnostics.statusCodeForDiagnostics(.referenceReady)
        registrationFailureEventCount = events.filter { event in
            guard event.stage == .frameRegistration,
                  let status = event.diagnostics.first(where: { $0.key == "registrationStatus" })?.value else {
                return false
            }

            return status != registeredStatus && status != referenceReadyStatus
        }.count

        globalChangeRejectedEventCount = Self.latestIntegerValue(for: "liveGlobalChangeRejectedFrameCount", in: valuesByKey)
        cadenceDroppedFrameCount = Self.latestIntegerValue(for: "liveCadenceDroppedFrameCount", in: valuesByKey)
        backpressureDroppedFrameCount = Self.latestIntegerValue(for: "liveBackpressureDroppedFrameCount", in: valuesByKey)
        invalidROIFrameCount = Self.latestIntegerValue(for: "liveInvalidROIFrameCount", in: valuesByKey)

        confidenceBandCounts = try [TemporalConfidenceBand.low, .medium, .high].compactMap { band in
            let count = detections.filter { $0.confidenceBand == band }.count
            return count > 0 ? try RangeValidationConfidenceBandCount(band: band, count: count) : nil
        }
    }

    private static func latestIntegerValue(for key: String, in valuesByKey: [String: [Double]]) -> Int {
        guard let value = valuesByKey[key]?.last else {
            return 0
        }

        return max(0, Int(value.rounded()))
    }
}

public struct RangeValidationBreakdownKey: Codable, Equatable, Sendable {
    public let targetDefinitionID: TargetDefinitionID?
    public let distance: Double?
    public let distanceUnit: DistanceUnit?
    public let caliber: String?
    public let deviceModel: String?
    public let testCondition: String?

    public init(manifest: ReplayManifest, context: RangeValidationContext) {
        targetDefinitionID = manifest.targetDefinitionID
        distance = manifest.distance
        distanceUnit = manifest.distanceUnit
        caliber = manifest.caliber
        deviceModel = context.deviceModel
        testCondition = context.testCondition
    }
}

public struct RangeValidationBreakdown: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let key: RangeValidationBreakdownKey
    public let metrics: RangeValidationMetrics
    public let diagnostics: RangeValidationDiagnosticsSummary

    public init(key: RangeValidationBreakdownKey, metrics: RangeValidationMetrics, diagnostics: RangeValidationDiagnosticsSummary) {
        self.id = [
            key.targetDefinitionID?.rawValue ?? "unknown-target",
            key.distance.map { String($0) } ?? "unknown-distance",
            key.distanceUnit?.rawValue ?? "unknown-unit",
            key.caliber ?? "unknown-caliber",
            key.deviceModel ?? "unknown-device",
            key.testCondition ?? "unknown-condition"
        ].joined(separator: "|")
        self.key = key
        self.metrics = metrics
        self.diagnostics = diagnostics
    }
}

public struct RangeValidationCohortBreakdown: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let key: RangeValidationBreakdownKey
    public let reportCount: Int
    public let metrics: RangeValidationMetrics

    public init(key: RangeValidationBreakdownKey, reportCount: Int, matches: [RangeValidationMatch]) throws {
        guard reportCount > 0 else {
            throw RangeValidationError.invalidReport
        }

        self.id = [
            key.targetDefinitionID?.rawValue ?? "unknown-target",
            key.distance.map { String($0) } ?? "unknown-distance",
            key.distanceUnit?.rawValue ?? "unknown-unit",
            key.caliber ?? "unknown-caliber",
            key.deviceModel ?? "unknown-device",
            key.testCondition ?? "unknown-condition"
        ].joined(separator: "|")
        self.key = key
        self.reportCount = reportCount
        self.metrics = RangeValidationMetrics(matches: matches)
    }
}

public struct RangeValidationReport: Codable, Equatable, Sendable, Identifiable {
    public let schemaVersion: Int
    public let id: String
    public let manifest: ReplayManifest
    public let configuration: RangeValidationConfiguration
    public let context: RangeValidationContext
    public let detections: [RangeValidationDetectedImpact]
    public let matches: [RangeValidationMatch]
    public let metrics: RangeValidationMetrics
    public let diagnostics: RangeValidationDiagnosticsSummary
    public let breakdowns: [RangeValidationBreakdown]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case manifest
        case configuration
        case context
        case detections
        case matches
        case metrics
        case diagnostics
        case breakdowns
    }

    public init(
        id: String,
        manifest: ReplayManifest,
        configuration: RangeValidationConfiguration,
        context: RangeValidationContext,
        detections: [RangeValidationDetectedImpact],
        matches: [RangeValidationMatch],
        diagnostics: RangeValidationDiagnosticsSummary
    ) throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RangeValidationError.invalidReport
        }

        let metrics = RangeValidationMetrics(matches: matches)
        schemaVersion = RangeValidationSchema.currentVersion
        self.id = id
        self.manifest = manifest
        self.configuration = configuration
        self.context = context
        self.detections = detections
        self.matches = matches
        self.metrics = metrics
        self.diagnostics = diagnostics
        self.breakdowns = [
            RangeValidationBreakdown(
                key: RangeValidationBreakdownKey(manifest: manifest, context: context),
                metrics: metrics,
                diagnostics: diagnostics
            )
        ]
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == RangeValidationSchema.currentVersion else {
            throw RangeValidationError.unsupportedValidationSchemaVersion(schemaVersion)
        }

        self.schemaVersion = schemaVersion
        id = try container.decode(String.self, forKey: .id)
        manifest = try container.decode(ReplayManifest.self, forKey: .manifest)
        configuration = try container.decode(RangeValidationConfiguration.self, forKey: .configuration)
        context = try container.decode(RangeValidationContext.self, forKey: .context)
        detections = try container.decode([RangeValidationDetectedImpact].self, forKey: .detections)
        matches = try container.decode([RangeValidationMatch].self, forKey: .matches)
        metrics = try container.decode(RangeValidationMetrics.self, forKey: .metrics)
        diagnostics = try container.decode(RangeValidationDiagnosticsSummary.self, forKey: .diagnostics)
        breakdowns = try container.decode([RangeValidationBreakdown].self, forKey: .breakdowns)
    }
}

public struct RangeValidationReportSuite: Codable, Equatable, Sendable, Identifiable {
    public let schemaVersion: Int
    public let id: String
    public let reports: [RangeValidationReport]
    public let cohortBreakdowns: [RangeValidationCohortBreakdown]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case reports
        case cohortBreakdowns
    }

    public init(id: String, reports: [RangeValidationReport]) throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RangeValidationError.invalidReport
        }

        schemaVersion = RangeValidationSchema.currentVersion
        self.id = id
        self.reports = reports.sorted {
            if $0.manifest.id == $1.manifest.id {
                return $0.id < $1.id
            }

            return $0.manifest.id < $1.manifest.id
        }
        cohortBreakdowns = try Self.cohortBreakdowns(for: self.reports)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == RangeValidationSchema.currentVersion else {
            throw RangeValidationError.unsupportedValidationSchemaVersion(schemaVersion)
        }

        self.schemaVersion = schemaVersion
        id = try container.decode(String.self, forKey: .id)
        reports = try container.decode([RangeValidationReport].self, forKey: .reports)
        cohortBreakdowns = try container.decode([RangeValidationCohortBreakdown].self, forKey: .cohortBreakdowns)
    }

    private static func cohortBreakdowns(for reports: [RangeValidationReport]) throws -> [RangeValidationCohortBreakdown] {
        var grouped: [String: (key: RangeValidationBreakdownKey, reports: [RangeValidationReport])] = [:]

        for report in reports {
            let key = RangeValidationBreakdownKey(manifest: report.manifest, context: report.context)
            let breakdownID = RangeValidationBreakdown(key: key, metrics: report.metrics, diagnostics: report.diagnostics).id
            var group = grouped[breakdownID] ?? (key: key, reports: [])
            group.reports.append(report)
            grouped[breakdownID] = group
        }

        return try grouped
            .keys
            .sorted()
            .map { id in
                guard let group = grouped[id] else {
                    throw RangeValidationError.invalidReport
                }

                return try RangeValidationCohortBreakdown(
                    key: group.key,
                    reportCount: group.reports.count,
                    matches: group.reports.flatMap(\.matches)
                )
            }
    }
}

public struct RangeValidationEngine: Sendable {
    public init() {}

    public func report(
        for replayResult: ReplayRunResult,
        detections: [RangeValidationDetectedImpact],
        configuration: RangeValidationConfiguration = .default,
        context: RangeValidationContext = RangeValidationContext()
    ) throws -> RangeValidationReport {
        try report(
            manifest: replayResult.manifest,
            processedFrameCount: replayResult.processedFrameCount,
            pipelineEvents: replayResult.frameResults.flatMap(\.events),
            detections: detections,
            configuration: configuration,
            context: context
        )
    }

    public func report(
        manifest: ReplayManifest,
        processedFrameCount: Int,
        pipelineEvents: [VisionPipelineEvent],
        detections: [RangeValidationDetectedImpact],
        configuration: RangeValidationConfiguration = .default,
        context: RangeValidationContext = RangeValidationContext()
    ) throws -> RangeValidationReport {
        let groundTruth = try manifest.expectedEvents.compactMap { event -> RangeValidationGroundTruthImpact? in
            guard event.kind == .shot, event.normalizedImpact != nil else {
                return nil
            }

            return try RangeValidationGroundTruthImpact(expectedEvent: event)
        }
        let orderedDetections = detections.sorted(by: detectionSort)
        let matches = try match(groundTruth: groundTruth, detections: orderedDetections, configuration: configuration)
        let diagnostics = try RangeValidationDiagnosticsSummary(
            processedFrameCount: processedFrameCount,
            events: pipelineEvents.sorted(by: eventSort),
            detections: orderedDetections
        )

        return try RangeValidationReport(
            id: "\(manifest.id)-validation",
            manifest: manifest,
            configuration: configuration,
            context: context,
            detections: orderedDetections,
            matches: matches,
            diagnostics: diagnostics
        )
    }

    public func detections(from liveImpactEvents: [LiveImpactEvent]) throws -> [RangeValidationDetectedImpact] {
        try liveImpactEvents.map(RangeValidationDetectedImpact.init(liveImpactEvent:)).sorted(by: detectionSort)
    }

    private func match(
        groundTruth: [RangeValidationGroundTruthImpact],
        detections: [RangeValidationDetectedImpact],
        configuration: RangeValidationConfiguration
    ) throws -> [RangeValidationMatch] {
        var usedDetectionIDs = Set<String>()
        var matches: [RangeValidationMatch] = []

        for expected in groundTruth.sorted(by: groundTruthSort) {
            let candidate = detections
                .filter { detection in
                    guard !usedDetectionIDs.contains(detection.id) else {
                        return false
                    }

                    let latency = detection.timestamp - expected.timestamp
                    guard latency >= 0 else {
                        return false
                    }

                    if let maximumConfirmationLatency = configuration.maximumConfirmationLatency,
                       latency > maximumConfirmationLatency {
                        return false
                    }

                    return coordinateError(expected.coordinate, detection.coordinate) <= configuration.coordinateTolerance
                }
                .min { lhs, rhs in
                    candidateSort(lhs, rhs, expected: expected)
                }

            if let candidate {
                usedDetectionIDs.insert(candidate.id)
                let error = coordinateError(expected.coordinate, candidate.coordinate)
                matches.append(
                    try RangeValidationMatch(
                        id: "detected-\(expected.id)-\(candidate.id)",
                        status: .detected,
                        groundTruth: expected,
                        detection: candidate,
                        coordinateError: error,
                        confirmationLatency: candidate.timestamp - expected.timestamp
                    )
                )
            } else {
                matches.append(
                    try RangeValidationMatch(
                        id: "missed-\(expected.id)",
                        status: .missed,
                        groundTruth: expected,
                        detection: nil,
                        coordinateError: nil,
                        confirmationLatency: nil
                    )
                )
            }
        }

        for detection in detections where !usedDetectionIDs.contains(detection.id) {
            matches.append(
                try RangeValidationMatch(
                    id: "false-positive-\(detection.id)",
                    status: .falsePositive,
                    groundTruth: nil,
                    detection: detection,
                    coordinateError: nil,
                    confirmationLatency: nil
                )
            )
        }

        return matches.sorted(by: matchSort)
    }

    private func coordinateError(_ lhs: NormalizedImagePoint, _ rhs: NormalizedImagePoint) -> Double {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func candidateSort(
        _ lhs: RangeValidationDetectedImpact,
        _ rhs: RangeValidationDetectedImpact,
        expected: RangeValidationGroundTruthImpact
    ) -> Bool {
        let lhsError = coordinateError(expected.coordinate, lhs.coordinate)
        let rhsError = coordinateError(expected.coordinate, rhs.coordinate)
        if lhsError != rhsError {
            return lhsError < rhsError
        }

        let lhsLatency = lhs.timestamp - expected.timestamp
        let rhsLatency = rhs.timestamp - expected.timestamp
        if lhsLatency != rhsLatency {
            return lhsLatency < rhsLatency
        }

        return detectionSort(lhs, rhs)
    }

    private func groundTruthSort(_ lhs: RangeValidationGroundTruthImpact, _ rhs: RangeValidationGroundTruthImpact) -> Bool {
        if lhs.timestamp == rhs.timestamp {
            return lhs.id < rhs.id
        }

        return lhs.timestamp < rhs.timestamp
    }

    private func detectionSort(_ lhs: RangeValidationDetectedImpact, _ rhs: RangeValidationDetectedImpact) -> Bool {
        if lhs.timestamp == rhs.timestamp {
            if lhs.frameSequenceIndex == rhs.frameSequenceIndex {
                return lhs.id < rhs.id
            }

            return lhs.frameSequenceIndex < rhs.frameSequenceIndex
        }

        return lhs.timestamp < rhs.timestamp
    }

    private func eventSort(_ lhs: VisionPipelineEvent, _ rhs: VisionPipelineEvent) -> Bool {
        if lhs.frameSequenceIndex == rhs.frameSequenceIndex {
            if lhs.frameTimestamp == rhs.frameTimestamp {
                return lhs.stage.rawValue < rhs.stage.rawValue
            }

            return lhs.frameTimestamp < rhs.frameTimestamp
        }

        return lhs.frameSequenceIndex < rhs.frameSequenceIndex
    }

    private func matchSort(_ lhs: RangeValidationMatch, _ rhs: RangeValidationMatch) -> Bool {
        let lhsTimestamp = lhs.groundTruth?.timestamp ?? lhs.detection?.timestamp ?? 0
        let rhsTimestamp = rhs.groundTruth?.timestamp ?? rhs.detection?.timestamp ?? 0
        if lhsTimestamp == rhsTimestamp {
            return lhs.id < rhs.id
        }

        return lhsTimestamp < rhsTimestamp
    }
}

public enum RangeValidationReportExporter {
    public static func jsonData(for report: RangeValidationReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(report)
    }

    public static func jsonData(for suite: RangeValidationReportSuite) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(suite)
    }
}

public enum RangeValidationError: Error, Equatable {
    case invalidConfiguration
    case invalidGroundTruth
    case invalidDetection
    case invalidMatch
    case invalidDiagnostics
    case invalidReport
    case unsupportedValidationSchemaVersion(Int)
}
