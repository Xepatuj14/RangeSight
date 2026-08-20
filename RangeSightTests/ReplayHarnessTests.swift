import Foundation
import XCTest
@testable import RangeSightCore

final class ReplayHarnessTests: XCTestCase {
    func testReplayProcessesFramesInDeterministicSourceOrder() async throws {
        let frames = try sampleFrames()
        let result = try await ReplayHarness.run(
            manifest: try ReplayManifest(id: "fixture-1"),
            configuration: try ReplayRunConfiguration(algorithmVersion: "test-detector-1"),
            frameSource: try ArrayReplayFrameSource(frames: frames),
            processor: RecordingProcessor()
        )

        let processedIndexes = result.frameResults.map(\.frame.sequenceIndex)
        let processedTimestamps = result.frameResults.map(\.frame.timestamp)
        let eventIndexes = result.frameResults.flatMap(\.events).map(\.frameSequenceIndex)

        XCTAssertEqual(result.completionReason, .endOfStream)
        XCTAssertEqual(result.processedFrameCount, 3)
        XCTAssertEqual(processedIndexes, [0, 1, 2])
        XCTAssertEqual(processedTimestamps, [0, 0.04, 0.11])
        XCTAssertEqual(eventIndexes, [0, 1, 2])
    }

    func testReplayPreservesStructuredPipelineEvents() async throws {
        let result = try await ReplayHarness.run(
            manifest: try ReplayManifest(id: "fixture-structured-result"),
            configuration: try ReplayRunConfiguration(algorithmVersion: "test-detector-1"),
            frameSource: try ArrayReplayFrameSource(frames: [try frame(index: 4, timestamp: 1.25)]),
            processor: RecordingProcessor()
        )

        let firstResult = try XCTUnwrap(result.frameResults.first)
        let firstEvent = try XCTUnwrap(firstResult.events.first)

        XCTAssertEqual(firstEvent.frameSequenceIndex, 4)
        XCTAssertEqual(firstEvent.frameTimestamp, 1.25)
        XCTAssertEqual(firstEvent.stage, .targetAcquisition)
        let expectedDiagnostics = [try VisionFrameDiagnostic(key: "fixtureFrameIndex", value: 4)]
        XCTAssertEqual(firstEvent.diagnostics, expectedDiagnostics)
    }

    func testReplayManifestSortsGroundTruthByTimestamp() throws {
        let manifest = try ReplayManifest(
            id: "fixture-ground-truth",
            expectedEvents: [
                try ReplayExpectedEvent(id: "shot-2", timestamp: 1.4, kind: .shot, normalizedImpact: try NormalizedTargetCoordinate(x: 0.55, y: 0.45)),
                try ReplayExpectedEvent(id: "shot-1", timestamp: 0.8, kind: .shot, normalizedImpact: try NormalizedTargetCoordinate(x: 0.5, y: 0.5))
            ]
        )

        XCTAssertEqual(manifest.expectedEvents.map(\.id), ["shot-1", "shot-2"])
        XCTAssertEqual(manifest.expectedEvents.map(\.timestamp), [0.8, 1.4])
    }

    func testArrayReplayFrameSourceRejectsInvalidInput() throws {
        XCTAssertThrowsError(
            try ArrayReplayFrameSource(frames: [])
        ) { error in
            XCTAssertEqual(error as? ReplayValidationError, .emptyFrameSequence)
        }

        XCTAssertThrowsError(
            try ArrayReplayFrameSource(
                frames: [
                    try frame(index: 1, timestamp: 0),
                    try frame(index: 1, timestamp: 0.1)
                ]
            )
        ) { error in
            XCTAssertEqual(error as? ReplayValidationError, .nonIncreasingFrameSequence)
        }

        XCTAssertThrowsError(
            try ArrayReplayFrameSource(
                frames: [
                    try frame(index: 1, timestamp: 0.2),
                    try frame(index: 2, timestamp: 0.1)
                ]
            )
        ) { error in
            XCTAssertEqual(error as? ReplayValidationError, .nonMonotonicFrameTimestamp)
        }
    }

    func testReplayReportsCancellationWithoutCorruptingPartialResults() async throws {
        let result = try await ReplayHarness.run(
            manifest: try ReplayManifest(id: "fixture-cancelled"),
            configuration: try ReplayRunConfiguration(algorithmVersion: "test-detector-1"),
            frameSource: try ArrayReplayFrameSource(frames: try sampleFrames()),
            processor: CancellingProcessor(cancelAfterFrameIndex: 1)
        )

        let processedIndexes = result.frameResults.map(\.frame.sequenceIndex)

        XCTAssertEqual(result.completionReason, .cancelled)
        XCTAssertEqual(processedIndexes, [0])
    }

    func testReplayConfigurationValidatesPlaybackSpeedSeparatelyFromTimestamps() throws {
        let frameByFrame = try ReplayRunConfiguration(algorithmVersion: "test-detector-1", playbackMode: .frameByFrame)
        let realtime = try ReplayRunConfiguration(algorithmVersion: "test-detector-1", playbackMode: .realtime)
        let accelerated = try ReplayRunConfiguration(algorithmVersion: "test-detector-1", playbackMode: .accelerated(4))

        XCTAssertNil(frameByFrame.playbackMode.speedMultiplier)
        XCTAssertEqual(realtime.playbackMode.speedMultiplier, 1)
        XCTAssertEqual(accelerated.playbackMode.speedMultiplier, 4)

        XCTAssertThrowsError(
            try ReplayRunConfiguration(algorithmVersion: "test-detector-1", playbackMode: .accelerated(0))
        ) { error in
            XCTAssertEqual(error as? ReplayValidationError, .invalidPlaybackSpeed)
        }
    }

    private func sampleFrames() throws -> [VisionFrame] {
        [
            try frame(index: 0, timestamp: 0),
            try frame(index: 1, timestamp: 0.04),
            try frame(index: 2, timestamp: 0.11)
        ]
    }

    private func frame(index: Int, timestamp: TimeInterval) throws -> VisionFrame {
        try VisionFrame(
            sequenceIndex: index,
            timestamp: timestamp,
            dimensions: try FrameDimensions(width: 1920, height: 1080),
            orientation: .landscapeRight,
            content: .fixtureData("frame-\(index)")
        )
    }
}

private struct RecordingProcessor: VisionFrameProcessor {
    mutating func process(_ frame: VisionFrame) async throws -> [VisionPipelineEvent] {
        [
            VisionPipelineEvent(
                frameSequenceIndex: frame.sequenceIndex,
                frameTimestamp: frame.timestamp,
                stage: .targetAcquisition,
                diagnostics: [
                    try VisionFrameDiagnostic(key: "fixtureFrameIndex", value: Double(frame.sequenceIndex))
                ]
            )
        ]
    }
}

private struct CancellingProcessor: VisionFrameProcessor {
    let cancelAfterFrameIndex: Int

    mutating func process(_ frame: VisionFrame) async throws -> [VisionPipelineEvent] {
        if frame.sequenceIndex >= cancelAfterFrameIndex {
            throw CancellationError()
        }

        return [
            VisionPipelineEvent(
                frameSequenceIndex: frame.sequenceIndex,
                frameTimestamp: frame.timestamp,
                stage: .targetAcquisition
            )
        ]
    }
}
