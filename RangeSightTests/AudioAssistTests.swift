import XCTest
@testable import RangeSightCore

final class AudioAssistTests: XCTestCase {
    func testImpulseDetectorEmitsOneCandidateForSharpTransient() throws {
        let configuration = try testConfiguration()
        var detector = AudioImpulseDetector(configuration: configuration)
        _ = try detector.process(window(timestamp: 0, samples: noiseSamples()))

        let candidates = try detector.process(window(timestamp: 0.04, samples: transientSamples()))

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.source, .synthetic)
        XCTAssertEqual(candidates.first?.diagnosticReason, .peakAndEnergyRise)
        XCTAssertGreaterThan(candidates.first?.peakAmplitude ?? 0, 0.8)
        XCTAssertGreaterThan(candidates.first?.energyRiseRatio ?? 0, 4)
    }

    func testImpulseDetectorIgnoresNoiseOnly() throws {
        let configuration = try testConfiguration()
        var detector = AudioImpulseDetector(configuration: configuration)

        let first = try detector.process(window(timestamp: 0, samples: noiseSamples()))
        let second = try detector.process(window(timestamp: 0.04, samples: noiseSamples()))

        XCTAssertEqual(first, [])
        XCTAssertEqual(second, [])
    }

    func testImpulseDetectorRefractorySuppressesEchoPeak() throws {
        let configuration = try testConfiguration(minimumEventSpacing: 0.2)
        var detector = AudioImpulseDetector(configuration: configuration)
        _ = try detector.process(window(timestamp: 0, samples: noiseSamples()))

        let first = try detector.process(window(timestamp: 0.04, samples: transientSamples()))
        let echo = try detector.process(window(timestamp: 0.10, samples: transientSamples()))

        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(echo, [])
    }

    func testAudioRingBufferReturnsOnlyCandidatesInVisualWindow() throws {
        let configuration = try AudioAssistConfiguration(
            preEventBufferDuration: 0.1,
            postEventVisualWindowDuration: 0.2,
            maximumBufferedEventCount: 6
        )
        var buffer = AudioImpulseRingBuffer(configuration: configuration)
        let old = try candidate(id: "old", timestamp: 1)
        let before = try candidate(id: "before", timestamp: 1.89)
        let start = try candidate(id: "start", timestamp: 1.9)
        let near = try candidate(id: "near", timestamp: 1.95, strength: 1.1)
        let strong = try candidate(id: "strong", timestamp: 2.05, strength: 2.0)
        let end = try candidate(id: "end", timestamp: 2.2)
        let after = try candidate(id: "after", timestamp: 2.21)

        [old, before, start, near, strong, end, after].forEach { buffer.append($0) }

        XCTAssertEqual(buffer.candidates.map(\.id), ["before", "start", "near", "strong", "end", "after"])
        XCTAssertEqual(buffer.candidatesSupportingVisualEvent(at: 2).map(\.id), ["start", "near", "strong", "end"])
        XCTAssertEqual(buffer.strongestCandidateSupportingVisualEvent(at: 2)?.id, "strong")
    }

    func testAudioConfigurationRejectsInvalidValues() {
        XCTAssertThrowsError(
            try AudioAssistConfiguration(
                sampleWindowDuration: 0,
                impulsePeakThreshold: 0.7,
                energyRiseThreshold: 4,
                minimumEventSpacing: 0.18,
                preEventBufferDuration: 0.2,
                postEventVisualWindowDuration: 0.35,
                baselineSmoothingFactor: 0.05,
                maximumBufferedEventCount: 8
            )
        ) { error in
            XCTAssertEqual(error as? AudioAssistValidationError, .invalidConfiguration)
        }

        XCTAssertThrowsError(
            try AudioAssistConfiguration(
                sampleWindowDuration: 0.02,
                impulsePeakThreshold: 0.7,
                energyRiseThreshold: 1,
                minimumEventSpacing: 0.18,
                preEventBufferDuration: 0.2,
                postEventVisualWindowDuration: 0.35,
                baselineSmoothingFactor: 0.05,
                maximumBufferedEventCount: 8
            )
        ) { error in
            XCTAssertEqual(error as? AudioAssistValidationError, .invalidConfiguration)
        }
    }

    func testPermissionStatesDoNotCreateVisualRequirement() async throws {
        let allowed = AudioAssistSessionController(source: FakeAudioSource(startState: .running))
        let denied = AudioAssistSessionController(source: FakeAudioSource(startState: .unavailable(.denied)))
        let unavailable = AudioAssistSessionController(source: FakeAudioSource(startState: .unavailable(.unavailable)))
        let disabled = AudioAssistSessionController(source: FakeAudioSource(startState: .running))

        let allowedState = await allowed.startIfEnabled(true)
        let deniedState = await denied.startIfEnabled(true)
        let unavailableState = await unavailable.startIfEnabled(true)
        let disabledState = await disabled.startIfEnabled(false)

        XCTAssertEqual(allowedState, .running)
        XCTAssertEqual(deniedState, .unavailable(.denied))
        XCTAssertEqual(unavailableState, .unavailable(.unavailable))
        XCTAssertEqual(disabledState, .stopped)
    }

    private func testConfiguration(minimumEventSpacing: TimeInterval = 0.18) throws -> AudioAssistConfiguration {
        try AudioAssistConfiguration(
            sampleWindowDuration: 0.02,
            impulsePeakThreshold: 0.7,
            energyRiseThreshold: 4,
            minimumEventSpacing: minimumEventSpacing,
            preEventBufferDuration: 0.2,
            postEventVisualWindowDuration: 0.35,
            baselineSmoothingFactor: 0.05,
            maximumBufferedEventCount: 8
        )
    }

    private func window(timestamp: TimeInterval, samples: [Float]) throws -> AudioSampleWindow {
        try AudioSampleWindow(startTimestamp: timestamp, sampleRate: 1_000, samples: samples)
    }

    private func noiseSamples() -> [Float] {
        Array(repeating: 0.02, count: 20)
    }

    private func transientSamples() -> [Float] {
        var samples = noiseSamples()
        samples[8] = 0.94
        samples[9] = 0.82
        return samples
    }

    private func candidate(id: String, timestamp: TimeInterval, strength: Double = 1) throws -> AudioImpulseCandidate {
        try AudioImpulseCandidate(
            id: id,
            timestamp: timestamp,
            peakAmplitude: 0.9,
            rmsEnergy: 0.22,
            baselineEnergy: 0.02,
            energyRiseRatio: 11,
            strength: strength,
            source: .synthetic,
            diagnosticReason: .peakAndEnergyRise
        )
    }
}

private struct FakeAudioSource: AudioImpulseCandidateSource {
    let startState: AudioAssistCaptureState

    func authorizationState() async -> AudioAssistAuthorizationState {
        switch startState {
        case .running:
            return .authorized
        case .unavailable(let state):
            return state
        default:
            return .notDetermined
        }
    }

    func requestAuthorization() async -> AudioAssistAuthorizationState {
        await authorizationState()
    }

    func start() async -> AudioAssistCaptureState {
        startState
    }

    func stop() async {}
}
