import Foundation
@preconcurrency import AVFoundation

public final class AVAudioEngineImpulseCandidateSource: AudioImpulseCandidateSource, @unchecked Sendable {
    private let engine: AVAudioEngine
    private let session: AVAudioSession
    private let queue = DispatchQueue(label: "com.rangesight.audio-impulse")
    private let onCandidate: @Sendable (AudioImpulseCandidate) -> Void
    private var detector: AudioImpulseDetector
    private var isTapInstalled = false
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?

    public init(
        configuration: AudioAssistConfiguration = .default,
        engine: AVAudioEngine = AVAudioEngine(),
        session: AVAudioSession = .sharedInstance(),
        onCandidate: @escaping @Sendable (AudioImpulseCandidate) -> Void
    ) {
        self.engine = engine
        self.session = session
        self.detector = AudioImpulseDetector(configuration: configuration)
        self.onCandidate = onCandidate
    }

    deinit {
        removeObservers()
        if isTapInstalled {
            engine.inputNode.removeTap(onBus: 0)
        }
        engine.stop()
    }

    public func authorizationState() async -> AudioAssistAuthorizationState {
        switch session.recordPermission {
        case .undetermined:
            return .notDetermined
        case .granted:
            return .authorized
        case .denied:
            return .denied
        @unknown default:
            return .restricted
        }
    }

    public func requestAuthorization() async -> AudioAssistAuthorizationState {
        await withCheckedContinuation { continuation in
            session.requestRecordPermission { [weak self] granted in
                guard granted else {
                    Task {
                        continuation.resume(returning: await self?.authorizationState() ?? .denied)
                    }
                    return
                }

                continuation.resume(returning: .authorized)
            }
        }
    }

    public func start() async -> AudioAssistCaptureState {
        let authorization = await authorizationState()
        let resolvedAuthorization: AudioAssistAuthorizationState
        if authorization == .notDetermined {
            resolvedAuthorization = await requestAuthorization()
        } else {
            resolvedAuthorization = authorization
        }

        guard resolvedAuthorization == .authorized else {
            return .unavailable(resolvedAuthorization)
        }

        do {
            try configureSession()
            try installTapIfNeeded()
            observeInterruptions()
            try engine.start()
            return .running
        } catch {
            stopSynchronously()
            return .failed(ReleasePermissionCopy.audioCaptureMessage(for: .failed("")))
        }
    }

    public func stop() async {
        stopSynchronously()
    }

    private func configureSession() throws {
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker])
        try session.setActive(true)
    }

    private func installTapIfNeeded() throws {
        guard !isTapInstalled else {
            return
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw AudioCaptureFailure.microphoneUnavailable
        }

        let bufferSize = AVAudioFrameCount(max(256, Int(format.sampleRate * detector.configuration.sampleWindowDuration)))
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, time in
            self?.process(buffer: buffer, time: time)
        }
        isTapInstalled = true
    }

    private func process(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        guard let channelData = buffer.floatChannelData,
              buffer.frameLength > 0 else {
            return
        }

        let frameLength = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        let sampleRate = buffer.format.sampleRate
        let timestamp = Self.timestamp(from: time, sampleRate: sampleRate)

        queue.async { [weak self] in
            guard var detector = self?.detector,
                  let window = try? AudioSampleWindow(
                    startTimestamp: timestamp,
                    sampleRate: sampleRate,
                    samples: samples,
                    source: .microphone
                  ),
                  let candidates = try? detector.process(window) else {
                return
            }

            self?.detector = detector
            candidates.forEach { self?.onCandidate($0) }
        }
    }

    private static func timestamp(from time: AVAudioTime, sampleRate: Double) -> TimeInterval {
        if time.hostTime != 0 {
            return AVAudioTime.seconds(forHostTime: time.hostTime)
        }

        if time.sampleTime >= 0 {
            return Double(time.sampleTime) / sampleRate
        }

        return 0
    }

    private func observeInterruptions() {
        guard interruptionObserver == nil,
              routeChangeObserver == nil else {
            return
        }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            guard self?.engine.isRunning == false else {
                return
            }
            try? self?.engine.start()
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            return
        }

        switch type {
        case .began:
            engine.pause()
        case .ended:
            try? session.setActive(true)
            try? engine.start()
        @unknown default:
            break
        }
    }

    private func stopSynchronously() {
        if isTapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }

        engine.stop()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        removeObservers()
    }

    private func removeObservers() {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }

        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
            self.routeChangeObserver = nil
        }
    }
}

public enum AudioCaptureFailure: Error, Equatable {
    case microphoneUnavailable
}
