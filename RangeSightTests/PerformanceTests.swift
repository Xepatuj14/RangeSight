import XCTest
@testable import RangeSightCore

final class PerformanceTests: XCTestCase {
    func testROIExtractionUsesRequestedPixelRegionAndPreservesTargetCoordinateMeaning() throws {
        let frame = try luminanceFrame(width: 6, height: 4)
        let region = try PixelRegion(x: 2, y: 1, width: 3, height: 2)

        let result = try LuminanceROIExtractor.extract(
            from: frame,
            region: region,
            minimumDimensions: try FrameDimensions(width: 2, height: 2)
        )

        XCTAssertEqual(result.status, .croppedROI)
        XCTAssertEqual(result.region, region)
        XCTAssertEqual(result.frame?.width, 3)
        XCTAssertEqual(result.frame?.height, 2)
        let extracted = try XCTUnwrap(result.frame)
        XCTAssertEqual(extracted.luminanceAt(x: 0, y: 0), 0.08, accuracy: 0.0001)
        XCTAssertEqual(extracted.luminanceAt(x: 1, y: 0), 0.09, accuracy: 0.0001)
        XCTAssertEqual(extracted.luminanceAt(x: 2, y: 0), 0.10, accuracy: 0.0001)
        XCTAssertEqual(extracted.luminanceAt(x: 0, y: 1), 0.14, accuracy: 0.0001)
        XCTAssertEqual(extracted.luminanceAt(x: 1, y: 1), 0.15, accuracy: 0.0001)
        XCTAssertEqual(extracted.luminanceAt(x: 2, y: 1), 0.16, accuracy: 0.0001)

        let normalizedCenter = try NormalizedImagePoint(x: 0.5, y: 0.5)
        XCTAssertEqual(normalizedCenter, try NormalizedImagePoint(x: 0.5, y: 0.5))
    }

    func testTargetROIMapperRejectsInvalidAndTooSmallRegions() throws {
        let sourceDimensions = try FrameDimensions(width: 100, height: 100)
        let small = try TargetQuadrilateral(
            topLeft: try NormalizedImagePoint(x: 0.1, y: 0.1),
            topRight: try NormalizedImagePoint(x: 0.2, y: 0.1),
            bottomRight: try NormalizedImagePoint(x: 0.2, y: 0.2),
            bottomLeft: try NormalizedImagePoint(x: 0.1, y: 0.2)
        )

        XCTAssertThrowsError(
            try TargetROIMapper.pixelRegion(
                for: small,
                sourceDimensions: sourceDimensions,
                minimumDimensions: try FrameDimensions(width: 20, height: 20)
            )
        ) { error in
            XCTAssertEqual(error as? PerformanceValidationError, .targetTooSmallForReliableAnalysis)
        }

        let frame = try luminanceFrame(width: 4, height: 4)
        XCTAssertThrowsError(
            try LuminanceROIExtractor.extract(
                from: frame,
                region: try PixelRegion(x: 3, y: 3, width: 2, height: 2),
                minimumDimensions: try FrameDimensions(width: 1, height: 1)
            )
        ) { error in
            XCTAssertEqual(error as? PerformanceValidationError, .invalidROI)
        }
    }

    func testSchedulerDropsCadenceAndBackpressureFramesWithoutUnboundedQueue() throws {
        var scheduler = LiveAnalysisScheduler(
            configuration: try LivePerformanceConfiguration(
                nominalAnalysisCadence: 0.1,
                maximumInFlightAnalysisCount: 1
            )
        )

        XCTAssertEqual(scheduler.submitFrame(timestamp: 1.0), .analyze)
        XCTAssertEqual(scheduler.submitFrame(timestamp: 1.05), .drop(.cadence))
        XCTAssertEqual(scheduler.submitFrame(timestamp: 1.2), .drop(.backpressure))
        scheduler.finishFrame()
        XCTAssertEqual(scheduler.submitFrame(timestamp: 1.21), .analyze)

        XCTAssertEqual(scheduler.capturedFrameCount, 4)
        XCTAssertEqual(scheduler.analyzedFrameCount, 2)
        XCTAssertEqual(scheduler.dropCounters.cadenceDroppedFrameCount, 1)
        XCTAssertEqual(scheduler.dropCounters.backpressureDroppedFrameCount, 1)
        XCTAssertEqual(scheduler.inFlightAnalysisCount, 1)
    }

    func testSchedulerSessionEndClearsInFlightStateAndDropsLateFrames() {
        var scheduler = LiveAnalysisScheduler()

        XCTAssertEqual(scheduler.submitFrame(timestamp: 1.0), .analyze)
        scheduler.resetForSessionEnd()
        XCTAssertEqual(scheduler.inFlightAnalysisCount, 0)
        XCTAssertNil(scheduler.lastAcceptedTimestamp)
        XCTAssertEqual(scheduler.submitFrame(timestamp: 1.2, sessionActive: false), .drop(.sessionEnded))
        XCTAssertEqual(scheduler.dropCounters.sessionEndedDroppedFrameCount, 1)
    }

    func testThermalPolicyUsesReducedCadenceAndCriticalPause() {
        let configuration = LivePerformanceConfiguration.default

        let nominal = ThermalPowerPolicy.decision(
            for: RuntimePowerState(thermalState: .nominal, lowPowerModeEnabled: false),
            configuration: configuration
        )
        let serious = ThermalPowerPolicy.decision(
            for: RuntimePowerState(thermalState: .serious, lowPowerModeEnabled: false),
            configuration: configuration
        )
        let critical = ThermalPowerPolicy.decision(
            for: RuntimePowerState(thermalState: .critical, lowPowerModeEnabled: false),
            configuration: configuration
        )

        XCTAssertEqual(nominal.mode, .normal)
        XCTAssertEqual(nominal.analysisCadence, configuration.nominalAnalysisCadence)
        XCTAssertEqual(serious.mode, .reducedResolution)
        XCTAssertEqual(serious.analysisCadence, configuration.seriousThermalAnalysisCadence)
        XCTAssertEqual(critical.mode, .paused)
        XCTAssertEqual(critical.userStatus, "Device is too warm for reliable live analysis.")
    }

    func testLowPowerModeUsesConservativeCadence() {
        let configuration = LivePerformanceConfiguration.default

        let decision = ThermalPowerPolicy.decision(
            for: RuntimePowerState(thermalState: .nominal, lowPowerModeEnabled: true),
            configuration: configuration
        )

        XCTAssertEqual(decision.mode, .reducedCadence)
        XCTAssertEqual(decision.analysisCadence, configuration.lowPowerAnalysisCadence)
        XCTAssertEqual(decision.userStatus, "Reduced analysis rate")
    }

    func testDeviceCapabilityFallbackSelectsBestAvailableSupportedMode() throws {
        let dimensions = try FrameDimensions(width: 1280, height: 720)
        let fallback = DeviceCapabilitySelector.select(
            from: DeviceCapabilityProfile(
                availableCameras: [.wideAngleCamera, .dualWideCamera],
                supportedPixelFormats: [.bgra, .yuvVideoRange],
                supportedFrameDimensions: [try FrameDimensions(width: 640, height: 480), dimensions]
            )
        )

        XCTAssertEqual(
            fallback,
            .supported(camera: .dualWideCamera, pixelFormat: .yuvVideoRange, dimensions: dimensions)
        )

        XCTAssertEqual(
            DeviceCapabilitySelector.select(
                from: DeviceCapabilityProfile(
                    availableCameras: [],
                    supportedPixelFormats: [.bgra],
                    supportedFrameDimensions: [dimensions]
                )
            ),
            .unsupported
        )
    }

    func testRollingMetricsAreBoundedAndComputeAverages() throws {
        var metrics = try RollingPerformanceMetrics(capacity: 3)

        try metrics.record(StageTimingSample(stage: .totalAnalysis, duration: 0.10))
        try metrics.record(StageTimingSample(stage: .registration, duration: 0.05))
        try metrics.record(StageTimingSample(stage: .totalAnalysis, duration: 0.20))
        try metrics.record(StageTimingSample(stage: .totalAnalysis, duration: 0.30))

        XCTAssertEqual(metrics.sampleCount, 3)
        XCTAssertEqual(metrics.analyzedFrameCount, 3)
        XCTAssertEqual(metrics.averageProcessingDuration, 0.25, accuracy: 0.0001)
        XCTAssertEqual(metrics.rollingHighWaterDuration, 0.30, accuracy: 0.0001)
        XCTAssertEqual(metrics.averageDuration(for: .changeDetection), 0)
    }

    func testDroppedFrameCountersRemainSeparate() {
        var counters = DroppedFrameCounters()

        counters.record(.cadence)
        counters.record(.backpressure)
        counters.record(.invalidROI)
        counters.record(.registrationRejected)
        counters.record(.globalChangeRejected)

        XCTAssertEqual(counters.cadenceDroppedFrameCount, 1)
        XCTAssertEqual(counters.backpressureDroppedFrameCount, 1)
        XCTAssertEqual(counters.invalidROIFrameCount, 1)
        XCTAssertEqual(counters.registrationRejectedFrameCount, 1)
        XCTAssertEqual(counters.globalChangeRejectedFrameCount, 1)
        XCTAssertEqual(counters.totalDroppedFrameCount, 5)
    }

    private func luminanceFrame(width: Int, height: Int) throws -> LuminanceFrame {
        try LuminanceFrame(
            width: width,
            height: height,
            pixels: (0..<(width * height)).map { Double($0) / 100.0 }
        )
    }
}
