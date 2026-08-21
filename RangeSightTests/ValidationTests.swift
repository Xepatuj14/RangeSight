import Foundation
import XCTest
@testable import RangeSightCore

final class ValidationTests: XCTestCase {
    func testValidationReportsDetectedMissedAndFalsePositiveImpacts() throws {
        let manifest = try ReplayManifest(
            id: "validation-fixture",
            expectedEvents: [
                expectedShot(id: "truth-1", timestamp: 1.0, x: 0.5, y: 0.5),
                expectedShot(id: "truth-2", timestamp: 2.0, x: 0.75, y: 0.5)
            ]
        )
        let detections = [
            try detection(id: "detected-1", frame: 12, timestamp: 1.16, x: 0.51, y: 0.49),
            try detection(id: "extra-1", frame: 30, timestamp: 3.0, x: 0.2, y: 0.2)
        ]

        let report = try RangeValidationEngine().report(
            manifest: manifest,
            processedFrameCount: 40,
            pipelineEvents: [],
            detections: detections,
            configuration: try RangeValidationConfiguration(coordinateTolerance: 0.04)
        )

        XCTAssertEqual(report.metrics.expectedImpactCount, 2)
        XCTAssertEqual(report.metrics.detectedImpactCount, 2)
        XCTAssertEqual(report.metrics.truePositiveCount, 1)
        XCTAssertEqual(report.metrics.missedImpactCount, 1)
        XCTAssertEqual(report.metrics.falsePositiveCount, 1)
        XCTAssertEqual(report.metrics.precision, 0.5)
        XCTAssertEqual(report.metrics.recall, 0.5)
        XCTAssertEqual(report.matches.map(\.status), [.detected, .missed, .falsePositive])
    }

    func testValidationRecordsCoordinateErrorAndConfirmationLatency() throws {
        let manifest = try ReplayManifest(
            id: "metric-fixture",
            expectedEvents: [
                expectedShot(id: "truth-1", timestamp: 5.0, x: 0.5, y: 0.5)
            ]
        )
        let report = try RangeValidationEngine().report(
            manifest: manifest,
            processedFrameCount: 12,
            pipelineEvents: [],
            detections: [
                try detection(id: "detected-1", frame: 8, timestamp: 5.25, x: 0.53, y: 0.54)
            ],
            configuration: try RangeValidationConfiguration(coordinateTolerance: 0.06)
        )

        let match = try XCTUnwrap(report.matches.first)
        XCTAssertEqual(match.coordinateError ?? -1, 0.05, accuracy: 0.000001)
        XCTAssertEqual(match.confirmationLatency ?? -1, 0.25, accuracy: 0.000001)
        XCTAssertEqual(report.metrics.meanCoordinateError ?? -1, 0.05, accuracy: 0.000001)
        XCTAssertEqual(report.metrics.maximumConfirmationLatency ?? -1, 0.25, accuracy: 0.000001)
    }

    func testMatchingIsDeterministicAndUsesNearestEligibleDetection() throws {
        let manifest = try ReplayManifest(
            id: "deterministic-fixture",
            expectedEvents: [
                expectedShot(id: "truth-1", timestamp: 1.0, x: 0.4, y: 0.4)
            ]
        )
        let fartherDetection = try detection(id: "a-farther", frame: 11, timestamp: 1.05, x: 0.43, y: 0.4)
        let nearerDetection = try detection(id: "b-nearer", frame: 12, timestamp: 1.10, x: 0.41, y: 0.4)

        let report = try RangeValidationEngine().report(
            manifest: manifest,
            processedFrameCount: 20,
            pipelineEvents: [],
            detections: [fartherDetection, nearerDetection],
            configuration: try RangeValidationConfiguration(coordinateTolerance: 0.05)
        )

        let detectedMatch = try XCTUnwrap(report.matches.first { $0.status == .detected })
        XCTAssertEqual(detectedMatch.detection?.id, "b-nearer")
        XCTAssertEqual(report.matches.last?.status, .falsePositive)
        XCTAssertEqual(report.matches.last?.detection?.id, "a-farther")
    }

    func testMaximumConfirmationLatencyPreventsLateMatch() throws {
        let manifest = try ReplayManifest(
            id: "latency-window-fixture",
            expectedEvents: [
                expectedShot(id: "truth-1", timestamp: 1.0, x: 0.5, y: 0.5)
            ]
        )

        let report = try RangeValidationEngine().report(
            manifest: manifest,
            processedFrameCount: 20,
            pipelineEvents: [],
            detections: [
                try detection(id: "late-detection", frame: 20, timestamp: 2.0, x: 0.5, y: 0.5)
            ],
            configuration: try RangeValidationConfiguration(coordinateTolerance: 0.02, maximumConfirmationLatency: 0.5)
        )

        XCTAssertEqual(report.metrics.truePositiveCount, 0)
        XCTAssertEqual(report.metrics.missedImpactCount, 1)
        XCTAssertEqual(report.metrics.falsePositiveCount, 1)
    }

    func testDiagnosticsSummaryAggregatesPipelineAndPerformanceCounters() throws {
        let registrationFailure = VisionPipelineEvent(
            frameSequenceIndex: 1,
            frameTimestamp: 0.1,
            stage: .frameRegistration,
            diagnostics: [
                try VisionFrameDiagnostic(key: "registrationStatus", value: FrameRegistrationDiagnostics.statusCodeForDiagnostics(.failed)),
                try VisionFrameDiagnostic(key: "registrationConfidence", value: 0.12)
            ]
        )
        let performance = VisionPipelineEvent(
            frameSequenceIndex: 2,
            frameTimestamp: 0.2,
            stage: .shotEventEmission,
            diagnostics: LiveImpactDiagnostics.diagnostics(
                for: LiveAnalysisDiagnostics(
                    capturedFrameCount: 10,
                    analyzedFrameCount: 8,
                    droppedAnalysisFrameCount: 2,
                    cadenceDroppedFrameCount: 1,
                    backpressureDroppedFrameCount: 1,
                    invalidROIFrameCount: 1,
                    globalChangeRejectedFrameCount: 2
                )
            )
        )

        let summary = try RangeValidationDiagnosticsSummary(
            processedFrameCount: 10,
            events: [registrationFailure, performance],
            detections: [
                try detection(id: "high", frame: 4, timestamp: 0.4, x: 0.4, y: 0.4, band: .high),
                try detection(id: "medium", frame: 5, timestamp: 0.5, x: 0.5, y: 0.5, band: .medium)
            ]
        )

        XCTAssertEqual(summary.processedFrameCount, 10)
        XCTAssertEqual(summary.pipelineEventCount, 2)
        XCTAssertEqual(summary.registrationFailureEventCount, 1)
        XCTAssertEqual(summary.globalChangeRejectedEventCount, 2)
        XCTAssertEqual(summary.cadenceDroppedFrameCount, 1)
        XCTAssertEqual(summary.backpressureDroppedFrameCount, 1)
        XCTAssertEqual(summary.invalidROIFrameCount, 1)
        XCTAssertEqual(summary.stageCounts.map(\.stage), [.frameRegistration, .shotEventEmission])
        XCTAssertEqual(summary.confidenceBandCounts.map(\.band), [.medium, .high])

        let registrationConfidence = try XCTUnwrap(summary.diagnosticAggregates.first { $0.key == "registrationConfidence" })
        XCTAssertEqual(registrationConfidence.average, 0.12, accuracy: 0.000001)
    }

    func testReportPreservesBreakdownMetadataAndRoundTripsThroughJSON() throws {
        let manifest = try ReplayManifest(
            id: "export-fixture",
            targetDefinitionID: try TargetDefinitionID("b8-repair-center"),
            distance: 15,
            distanceUnit: .yard,
            caliber: "9mm",
            expectedEvents: [
                expectedShot(id: "truth-1", timestamp: 1.0, x: 0.5, y: 0.5)
            ]
        )
        let context = RangeValidationContext(
            deviceModel: "iPhone Test Device",
            testCondition: "indoor-lane-a",
            appVersion: "18.0-test",
            detectorVersion: "slice-18-fixture",
            metadata: ["lighting": "mixed"]
        )
        let report = try RangeValidationEngine().report(
            manifest: manifest,
            processedFrameCount: 15,
            pipelineEvents: [],
            detections: [
                try detection(id: "detected-1", frame: 4, timestamp: 1.12, x: 0.5, y: 0.5)
            ],
            context: context
        )

        let data = try RangeValidationReportExporter.jsonData(for: report)
        let decoded = try JSONDecoder().decode(RangeValidationReport.self, from: data)
        let targetDefinitionID = try TargetDefinitionID("b8-repair-center")

        XCTAssertEqual(decoded, report)
        XCTAssertEqual(decoded.schemaVersion, RangeValidationSchema.currentVersion)
        XCTAssertEqual(decoded.breakdowns.first?.key.targetDefinitionID, targetDefinitionID)
        XCTAssertEqual(decoded.breakdowns.first?.key.distance, 15)
        XCTAssertEqual(decoded.breakdowns.first?.key.caliber, "9mm")
        XCTAssertEqual(decoded.breakdowns.first?.key.deviceModel, "iPhone Test Device")
        XCTAssertEqual(decoded.breakdowns.first?.key.testCondition, "indoor-lane-a")
    }

    func testReportSuiteGroupsMetricsByRangeCondition() throws {
        let firstReport = try report(
            id: "distance-7",
            distance: 7,
            condition: "lane-a",
            truthID: "truth-7",
            detectionID: "detected-7"
        )
        let secondReport = try report(
            id: "distance-15",
            distance: 15,
            condition: "lane-a",
            truthID: "truth-15",
            detectionID: nil
        )

        let suite = try RangeValidationReportSuite(id: "range-day-1", reports: [secondReport, firstReport])
        let data = try RangeValidationReportExporter.jsonData(for: suite)
        let decoded = try JSONDecoder().decode(RangeValidationReportSuite.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, RangeValidationSchema.currentVersion)
        XCTAssertEqual(decoded.reports.map(\.manifest.id), ["distance-15", "distance-7"])
        XCTAssertEqual(decoded.cohortBreakdowns.count, 2)

        let sevenYard = try XCTUnwrap(decoded.cohortBreakdowns.first { $0.key.distance == 7 })
        XCTAssertEqual(sevenYard.metrics.truePositiveCount, 1)
        XCTAssertEqual(sevenYard.metrics.recall ?? -1, 1)

        let fifteenYard = try XCTUnwrap(decoded.cohortBreakdowns.first { $0.key.distance == 15 })
        XCTAssertEqual(fifteenYard.metrics.missedImpactCount, 1)
        XCTAssertEqual(fifteenYard.metrics.recall ?? -1, 0)
    }

    func testValidationReportRejectsUnsupportedFutureSchema() throws {
        let report = try report(
            id: "future-schema-fixture",
            distance: 7,
            condition: "lane-a",
            truthID: "truth-1",
            detectionID: "detected-1"
        )
        let data = try RangeValidationReportExporter.jsonData(for: report)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var futureObject = object
        futureObject["schemaVersion"] = RangeValidationSchema.currentVersion + 1
        let futureData = try JSONSerialization.data(withJSONObject: futureObject, options: [.sortedKeys])

        do {
            _ = try JSONDecoder().decode(RangeValidationReport.self, from: futureData)
            XCTFail("Expected unsupported validation schema to fail.")
        } catch RangeValidationError.unsupportedValidationSchemaVersion(let version) {
            XCTAssertEqual(version, RangeValidationSchema.currentVersion + 1)
        }
    }

    func testLiveImpactEventsConvertToValidationDetections() throws {
        let liveEvent = try LiveImpactEvent(
            id: "live-impact-1",
            shotIndex: 1,
            frameSequenceIndex: 8,
            timestamp: 1.2,
            normalizedCoordinate: try NormalizedImagePoint(x: 0.45, y: 0.55),
            confidence: 0.91,
            confidenceBand: .high,
            temporalCandidateID: "temporal-1"
        )

        let detections = try RangeValidationEngine().detections(from: [liveEvent])

        XCTAssertEqual(detections.count, 1)
        XCTAssertEqual(detections.first?.id, "live-impact-1")
        XCTAssertEqual(detections.first?.sourceEventID, "temporal-1")
        XCTAssertEqual(detections.first?.confidenceBand, .high)
    }

    private func expectedShot(
        id: String,
        timestamp: TimeInterval,
        x: Double,
        y: Double
    ) throws -> ReplayExpectedEvent {
        try ReplayExpectedEvent(
            id: id,
            timestamp: timestamp,
            kind: .shot,
            normalizedImpact: try NormalizedTargetCoordinate(x: x, y: y)
        )
    }

    private func detection(
        id: String,
        frame: Int,
        timestamp: TimeInterval,
        x: Double,
        y: Double,
        band: TemporalConfidenceBand = .high
    ) throws -> RangeValidationDetectedImpact {
        try RangeValidationDetectedImpact(
            id: id,
            frameSequenceIndex: frame,
            timestamp: timestamp,
            coordinate: try NormalizedImagePoint(x: x, y: y),
            confidence: band == .high ? 0.92 : 0.72,
            confidenceBand: band
        )
    }

    private func report(
        id: String,
        distance: Double,
        condition: String,
        truthID: String,
        detectionID: String?
    ) throws -> RangeValidationReport {
        let manifest = try ReplayManifest(
            id: id,
            targetDefinitionID: try TargetDefinitionID("validation-target"),
            distance: distance,
            distanceUnit: .yard,
            caliber: "9mm",
            expectedEvents: [
                expectedShot(id: truthID, timestamp: 1.0, x: 0.5, y: 0.5)
            ]
        )
        let detections: [RangeValidationDetectedImpact]
        if let detectionID = detectionID {
            detections = [
                try detection(id: detectionID, frame: 5, timestamp: 1.1, x: 0.5, y: 0.5)
            ]
        } else {
            detections = []
        }

        return try RangeValidationEngine().report(
            manifest: manifest,
            processedFrameCount: 10,
            pipelineEvents: [],
            detections: detections,
            context: RangeValidationContext(deviceModel: "iPhone Test Device", testCondition: condition)
        )
    }
}
