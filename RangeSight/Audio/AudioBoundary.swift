import Foundation

public enum AudioAssistAuthorizationState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unavailable
}

public enum AudioAssistCaptureState: Equatable, Sendable {
    case idle
    case requestingPermission
    case running
    case stopped
    case unavailable(AudioAssistAuthorizationState)
    case interrupted
    case failed(String)
}

public enum AudioImpulseSource: String, Codable, Equatable, Sendable {
    case microphone
    case replay
    case synthetic
}

public enum AudioImpulseReason: String, Codable, Equatable, Sendable {
    case peakAndEnergyRise
    case refractorySuppressed
}

public struct AudioAssistConfiguration: Codable, Equatable, Sendable {
    public let sampleWindowDuration: TimeInterval
    public let impulsePeakThreshold: Double
    public let energyRiseThreshold: Double
    public let minimumEventSpacing: TimeInterval
    public let preEventBufferDuration: TimeInterval
    public let postEventVisualWindowDuration: TimeInterval
    public let baselineSmoothingFactor: Double
    public let maximumBufferedEventCount: Int

    public init(
        sampleWindowDuration: TimeInterval = 0.02,
        impulsePeakThreshold: Double = 0.72,
        energyRiseThreshold: Double = 4,
        minimumEventSpacing: TimeInterval = 0.18,
        preEventBufferDuration: TimeInterval = 0.35,
        postEventVisualWindowDuration: TimeInterval = 0.45,
        baselineSmoothingFactor: Double = 0.08,
        maximumBufferedEventCount: Int = 32
    ) throws {
        guard sampleWindowDuration > 0,
              impulsePeakThreshold > 0,
              energyRiseThreshold > 1,
              minimumEventSpacing >= 0,
              preEventBufferDuration >= 0,
              postEventVisualWindowDuration >= 0,
              (0...1).contains(baselineSmoothingFactor),
              maximumBufferedEventCount > 0,
              sampleWindowDuration.isFinite,
              impulsePeakThreshold.isFinite,
              energyRiseThreshold.isFinite,
              minimumEventSpacing.isFinite,
              preEventBufferDuration.isFinite,
              postEventVisualWindowDuration.isFinite,
              baselineSmoothingFactor.isFinite else {
            throw AudioAssistValidationError.invalidConfiguration
        }

        self.sampleWindowDuration = sampleWindowDuration
        self.impulsePeakThreshold = impulsePeakThreshold
        self.energyRiseThreshold = energyRiseThreshold
        self.minimumEventSpacing = minimumEventSpacing
        self.preEventBufferDuration = preEventBufferDuration
        self.postEventVisualWindowDuration = postEventVisualWindowDuration
        self.baselineSmoothingFactor = baselineSmoothingFactor
        self.maximumBufferedEventCount = maximumBufferedEventCount
    }

    public static let `default` = try! AudioAssistConfiguration()
}

public struct AudioSampleWindow: Equatable, Sendable {
    public let startTimestamp: TimeInterval
    public let sampleRate: Double
    public let samples: [Float]
    public let source: AudioImpulseSource

    public init(
        startTimestamp: TimeInterval,
        sampleRate: Double,
        samples: [Float],
        source: AudioImpulseSource = .synthetic
    ) throws {
        guard startTimestamp >= 0,
              startTimestamp.isFinite,
              sampleRate > 0,
              sampleRate.isFinite,
              !samples.isEmpty else {
            throw AudioAssistValidationError.invalidSampleWindow
        }

        self.startTimestamp = startTimestamp
        self.sampleRate = sampleRate
        self.samples = samples
        self.source = source
    }
}

public struct AudioImpulseCandidate: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let timestamp: TimeInterval
    public let peakAmplitude: Double
    public let rmsEnergy: Double
    public let baselineEnergy: Double
    public let energyRiseRatio: Double
    public let strength: Double
    public let source: AudioImpulseSource
    public let diagnosticReason: AudioImpulseReason

    public init(
        id: String,
        timestamp: TimeInterval,
        peakAmplitude: Double,
        rmsEnergy: Double,
        baselineEnergy: Double,
        energyRiseRatio: Double,
        strength: Double,
        source: AudioImpulseSource,
        diagnosticReason: AudioImpulseReason
    ) throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              timestamp >= 0,
              peakAmplitude >= 0,
              rmsEnergy >= 0,
              baselineEnergy >= 0,
              energyRiseRatio >= 0,
              strength >= 0,
              timestamp.isFinite,
              peakAmplitude.isFinite,
              rmsEnergy.isFinite,
              baselineEnergy.isFinite,
              energyRiseRatio.isFinite,
              strength.isFinite else {
            throw AudioAssistValidationError.invalidCandidate
        }

        self.id = id
        self.timestamp = timestamp
        self.peakAmplitude = peakAmplitude
        self.rmsEnergy = rmsEnergy
        self.baselineEnergy = baselineEnergy
        self.energyRiseRatio = energyRiseRatio
        self.strength = strength
        self.source = source
        self.diagnosticReason = diagnosticReason
    }
}

public struct AudioImpulseDetector: Sendable {
    public let configuration: AudioAssistConfiguration
    private var baselineEnergy: Double?
    private var lastAcceptedTimestamp: TimeInterval?
    private var nextCandidateNumber = 1

    public init(configuration: AudioAssistConfiguration = .default) {
        self.configuration = configuration
    }

    public mutating func process(_ window: AudioSampleWindow) throws -> [AudioImpulseCandidate] {
        let metrics = Self.metrics(for: window)
        let baseline = max(baselineEnergy ?? metrics.rmsEnergy, 0.000001)
        let energyRise = metrics.rmsEnergy / baseline
        let peakTime = window.startTimestamp + Double(metrics.peakIndex) / window.sampleRate
        let isImpulse = metrics.peakAmplitude >= configuration.impulsePeakThreshold &&
            energyRise >= configuration.energyRiseThreshold

        guard isImpulse else {
            updateBaseline(with: metrics.rmsEnergy)
            return []
        }

        if let lastAcceptedTimestamp,
           peakTime - lastAcceptedTimestamp < configuration.minimumEventSpacing {
            return []
        }

        lastAcceptedTimestamp = peakTime
        let candidate = try AudioImpulseCandidate(
            id: "audio-impulse-\(nextCandidateNumber)",
            timestamp: peakTime,
            peakAmplitude: metrics.peakAmplitude,
            rmsEnergy: metrics.rmsEnergy,
            baselineEnergy: baseline,
            energyRiseRatio: energyRise,
            strength: max(
                metrics.peakAmplitude / configuration.impulsePeakThreshold,
                energyRise / configuration.energyRiseThreshold
            ),
            source: window.source,
            diagnosticReason: .peakAndEnergyRise
        )
        nextCandidateNumber += 1
        return [candidate]
    }

    private mutating func updateBaseline(with rmsEnergy: Double) {
        guard let baselineEnergy else {
            self.baselineEnergy = rmsEnergy
            return
        }

        let alpha = configuration.baselineSmoothingFactor
        self.baselineEnergy = baselineEnergy * (1 - alpha) + rmsEnergy * alpha
    }

    private static func metrics(for window: AudioSampleWindow) -> (peakAmplitude: Double, peakIndex: Int, rmsEnergy: Double) {
        var peakAmplitude = 0.0
        var peakIndex = 0
        var squareSum = 0.0

        for (index, sample) in window.samples.enumerated() {
            let amplitude = Double(abs(sample))
            squareSum += amplitude * amplitude
            if amplitude > peakAmplitude {
                peakAmplitude = amplitude
                peakIndex = index
            }
        }

        return (
            peakAmplitude,
            peakIndex,
            sqrt(squareSum / Double(window.samples.count))
        )
    }
}

public struct AudioImpulseRingBuffer: Codable, Equatable, Sendable {
    public let configuration: AudioAssistConfiguration
    public private(set) var candidates: [AudioImpulseCandidate]

    public init(
        configuration: AudioAssistConfiguration = .default,
        candidates: [AudioImpulseCandidate] = []
    ) {
        self.configuration = configuration
        self.candidates = candidates
        trim()
    }

    public mutating func append(_ candidate: AudioImpulseCandidate) {
        candidates.append(candidate)
        trim()
    }

    public func candidatesSupportingVisualEvent(at timestamp: TimeInterval) -> [AudioImpulseCandidate] {
        candidates.filter { candidate in
            candidate.timestamp >= timestamp - configuration.preEventBufferDuration &&
                candidate.timestamp <= timestamp + configuration.postEventVisualWindowDuration
        }
    }

    public func strongestCandidateSupportingVisualEvent(at timestamp: TimeInterval) -> AudioImpulseCandidate? {
        candidatesSupportingVisualEvent(at: timestamp).max { lhs, rhs in
            if lhs.strength == rhs.strength {
                return lhs.timestamp < rhs.timestamp
            }

            return lhs.strength < rhs.strength
        }
    }

    private mutating func trim() {
        candidates = candidates
            .sorted { lhs, rhs in
                if lhs.timestamp == rhs.timestamp {
                    return lhs.id < rhs.id
                }

                return lhs.timestamp < rhs.timestamp
            }

        if candidates.count > configuration.maximumBufferedEventCount {
            candidates.removeFirst(candidates.count - configuration.maximumBufferedEventCount)
        }
    }
}

public enum AudioVisualCorrelation {
    public static func audioSupport(
        forVisualTimestamp timestamp: TimeInterval,
        in buffer: AudioImpulseRingBuffer
    ) -> AudioImpulseCandidate? {
        buffer.strongestCandidateSupportingVisualEvent(at: timestamp)
    }
}

public protocol AudioImpulseCandidateSource: Sendable {
    func authorizationState() async -> AudioAssistAuthorizationState
    func requestAuthorization() async -> AudioAssistAuthorizationState
    func start() async -> AudioAssistCaptureState
    func stop() async
}

public actor AudioAssistSessionController {
    private let source: AudioImpulseCandidateSource
    public private(set) var captureState: AudioAssistCaptureState = .idle

    public init(source: AudioImpulseCandidateSource) {
        self.source = source
    }

    @discardableResult
    public func startIfEnabled(_ isEnabled: Bool) async -> AudioAssistCaptureState {
        guard isEnabled else {
            captureState = .stopped
            return captureState
        }

        captureState = .requestingPermission
        captureState = await source.start()
        return captureState
    }

    public func stop() async {
        await source.stop()
        captureState = .stopped
    }
}

public enum AudioAssistValidationError: Error, Equatable {
    case invalidConfiguration
    case invalidSampleWindow
    case invalidCandidate
}
