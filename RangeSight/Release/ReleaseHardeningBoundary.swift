import Foundation

public enum ReleaseDefectSeverity: String, Codable, CaseIterable, Equatable, Sendable {
    case p0
    case p1
    case p2
    case p3
}

public enum ReleaseReadinessVerdict: String, Codable, Equatable, Sendable {
    case readyForTestFlight
    case readyForInternalTestFlightOnly
    case notReady
}

public struct ReleaseDefect: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let severity: ReleaseDefectSeverity
    public let summary: String

    public init(id: String, severity: ReleaseDefectSeverity, summary: String) throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReleaseHardeningValidationError.invalidReleaseDefect
        }

        self.id = id
        self.severity = severity
        self.summary = summary
    }
}

public enum ReleaseGateEvaluator {
    public static func verdict(for defects: [ReleaseDefect], hasPhysicalDeviceValidation: Bool) -> ReleaseReadinessVerdict {
        if defects.contains(where: { $0.severity == .p0 || $0.severity == .p1 }) {
            return .notReady
        }

        return hasPhysicalDeviceValidation ? .readyForTestFlight : .readyForInternalTestFlightOnly
    }
}

public enum ReleasePrivacyDisclosure {
    public static let onDeviceAnalysis = "Target analysis runs on device during active range sessions."
    public static let cameraRetention = "Raw camera frames are not uploaded by default and are not retained as full video by the current app storage model."
    public static let audioRetention = "Audio Assist is optional. Microphone samples are processed transiently for impulse timing and are not uploaded by default."
    public static let offlineUse = "Core range workflows do not require an account or network connection."
    public static let exports = "Exports leave app-controlled storage only when the user explicitly shares or exports them."

    public static let allCopy: [String] = [
        onDeviceAnalysis,
        cameraRetention,
        audioRetention,
        offlineUse,
        exports
    ]
}

public enum ReleasePermissionCopy {
    public static func cameraMessage(for state: CameraAuthorizationState) -> String {
        switch state {
        case .notDetermined:
            return "Camera access is requested when you open camera setup for an active range session."
        case .authorized:
            return "Camera access is enabled for active target monitoring."
        case .denied:
            return "Camera access is required to monitor a target. Enable Camera in Settings."
        case .restricted:
            return "Camera access is restricted on this device. RangeSight remains navigable, but live monitoring is unavailable."
        }
    }

    public static func microphoneMessage(for state: AudioAssistAuthorizationState) -> String {
        switch state {
        case .notDetermined:
            return "Microphone access is requested only when optional Audio Assist is enabled."
        case .authorized:
            return "Audio Assist can listen for transient impulses, but visual confirmation is still required."
        case .denied:
            return "Audio Assist is unavailable. Visual detection will continue."
        case .restricted, .unavailable:
            return "Audio Assist is unavailable on this device. Visual detection will continue."
        }
    }

    public static func audioCaptureMessage(for state: AudioAssistCaptureState) -> String {
        switch state {
        case .idle:
            return "Audio Assist is idle."
        case .requestingPermission:
            return "Requesting optional microphone access for Audio Assist."
        case .running:
            return "Audio Assist is running. Visual confirmation is still required."
        case .stopped:
            return "Audio Assist is off. Visual detection will continue."
        case .unavailable(let authorization):
            return microphoneMessage(for: authorization)
        case .interrupted:
            return "Audio Assist was interrupted. Visual detection will continue."
        case .failed:
            return "Audio Assist could not start. Visual detection will continue."
        }
    }

    public static func cameraSessionMessage(for failure: CameraSessionFailure) -> String {
        switch failure {
        case .cameraUnavailable:
            return "Camera is unavailable. Check the device camera and try again."
        case .cannotAddInput, .cannotAddOutput:
            return "Camera couldn't be configured. Try again or go back to setup."
        case .startupTimedOut:
            return "Camera didn't start. Try again or go back to setup."
        }
    }
}

public enum ReleaseHardeningValidationError: Error, Equatable {
    case invalidReleaseDefect
    case invalidTimeoutPolicy
}

public enum ReleaseFlowOperation: String, Codable, CaseIterable, Equatable, Sendable {
    case cameraStartup
    case targetLockAttempt
    case baselineAcquisition
    case persistenceSave
    case validationExport
}

public struct ReleaseTimeoutPolicy: Codable, Equatable, Sendable {
    public let operation: ReleaseFlowOperation
    public let duration: TimeInterval?
    public let reason: String
    public let recoveryAction: String

    public init(
        operation: ReleaseFlowOperation,
        duration: TimeInterval?,
        reason: String,
        recoveryAction: String
    ) throws {
        if let duration {
            guard duration > 0, duration.isFinite else {
                throw ReleaseHardeningValidationError.invalidTimeoutPolicy
            }
        }

        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !recoveryAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReleaseHardeningValidationError.invalidTimeoutPolicy
        }

        self.operation = operation
        self.duration = duration
        self.reason = reason
        self.recoveryAction = recoveryAction
    }

    public static let cameraStartup = ReleaseTimeoutPolicy.unchecked(
        operation: .cameraStartup,
        duration: 8,
        reason: "AVFoundation configuration/startup depends on device hardware and must not leave the preview in Starting forever.",
        recoveryAction: "Show retry/back guidance."
    )

    public static let targetLockAttempt = ReleaseTimeoutPolicy.unchecked(
        operation: .targetLockAttempt,
        duration: 5,
        reason: "A single lock attempt should be bounded; the active preview itself remains user-controlled.",
        recoveryAction: "Allow reposition and retry or back to setup."
    )

    public static let baselineAcquisition = ReleaseTimeoutPolicy.unchecked(
        operation: .baselineAcquisition,
        duration: 8,
        reason: "Starting a string should not wait indefinitely for valid baseline frames.",
        recoveryAction: "Require re-lock, retry, end, or cancel."
    )

    public static let persistenceSave = ReleaseTimeoutPolicy.unchecked(
        operation: .persistenceSave,
        duration: nil,
        reason: "Local repository writes are atomic synchronous file operations behind async boundaries; failures throw.",
        recoveryAction: "Exit saving state, show retry, preserve in-memory session."
    )

    public static let validationExport = ReleaseTimeoutPolicy.unchecked(
        operation: .validationExport,
        duration: nil,
        reason: "Validation export is deterministic encoding/writing with throwing failure paths, not a long external wait.",
        recoveryAction: "Report export failure and allow retry/cancel."
    )

    public static let defaults: [ReleaseTimeoutPolicy] = [
        cameraStartup,
        targetLockAttempt,
        baselineAcquisition,
        persistenceSave,
        validationExport
    ]

    private static func unchecked(
        operation: ReleaseFlowOperation,
        duration: TimeInterval?,
        reason: String,
        recoveryAction: String
    ) -> ReleaseTimeoutPolicy {
        ReleaseTimeoutPolicy(
            operation: operation,
            duration: duration,
            reason: reason,
            recoveryAction: recoveryAction,
            validated: ()
        )
    }

    private init(
        operation: ReleaseFlowOperation,
        duration: TimeInterval?,
        reason: String,
        recoveryAction: String,
        validated: Void
    ) {
        self.operation = operation
        self.duration = duration
        self.reason = reason
        self.recoveryAction = recoveryAction
    }
}

public enum ReleaseUserFacingState: String, Codable, CaseIterable, Equatable, Sendable {
    case home
    case setup
    case cameraPermission
    case cameraStarting
    case targetFraming
    case targetLockBlocked
    case targetLocked
    case baselineAcquiring
    case monitoring
    case monitoringDegraded
    case reviewing
    case saving
    case saveFailed
    case historyLoading
    case historyEmpty
    case historyError
}

public struct ReleaseUserEscape: Codable, Equatable, Sendable {
    public let state: ReleaseUserFacingState
    public let automaticTransition: String?
    public let escapeActions: [String]

    public init(state: ReleaseUserFacingState, automaticTransition: String? = nil, escapeActions: [String] = []) {
        self.state = state
        self.automaticTransition = automaticTransition
        self.escapeActions = escapeActions
    }

    public var satisfiesEscapeInvariant: Bool {
        automaticTransition?.isEmpty == false || !escapeActions.isEmpty
    }
}

public enum ReleaseFlowAudit {
    public static let userEscapes: [ReleaseUserEscape] = [
        ReleaseUserEscape(state: .home, escapeActions: ["New Session", "History", "Settings"]),
        ReleaseUserEscape(state: .setup, escapeActions: ["Continue to Camera", "Home tab"]),
        ReleaseUserEscape(state: .cameraPermission, automaticTransition: "Permission callback", escapeActions: ["Back/Home tab"]),
        ReleaseUserEscape(state: .cameraStarting, automaticTransition: "Camera startup timeout", escapeActions: ["Back/Home tab"]),
        ReleaseUserEscape(state: .targetFraming, escapeActions: ["Back/Home tab", "Change lock source"]),
        ReleaseUserEscape(state: .targetLockBlocked, escapeActions: ["Adjust framing", "Change lock source", "Back/Home tab"]),
        ReleaseUserEscape(state: .targetLocked, escapeActions: ["Lock Target", "Back/Home tab"]),
        ReleaseUserEscape(state: .baselineAcquiring, automaticTransition: "Baseline timeout", escapeActions: ["End String", "Back/Home tab"]),
        ReleaseUserEscape(state: .monitoring, escapeActions: ["End String", "Pause"]),
        ReleaseUserEscape(state: .monitoringDegraded, escapeActions: ["End String", "Re-lock/Pause"]),
        ReleaseUserEscape(state: .reviewing, escapeActions: ["Save String", "Clear selection", "Cancel add/move"]),
        ReleaseUserEscape(state: .saving, automaticTransition: "Repository success or failure"),
        ReleaseUserEscape(state: .saveFailed, escapeActions: ["Retry Save", "Discard/Back"]),
        ReleaseUserEscape(state: .historyLoading, automaticTransition: "Repository success or failure", escapeActions: ["Home/Settings tab"]),
        ReleaseUserEscape(state: .historyEmpty, escapeActions: ["Home/Settings tab"]),
        ReleaseUserEscape(state: .historyError, escapeActions: ["Retry by reopening History", "Home/Settings tab"])
    ]

    public static var satisfiesUserEscapeInvariant: Bool {
        userEscapes.allSatisfy(\.satisfiesEscapeInvariant)
    }
}

public enum ReleaseSaveFlowState: String, Codable, Equatable, Sendable {
    case review
    case saving
    case saved
    case failed
    case discarded
}

public enum ReleaseSaveFlowEvent: String, Codable, Equatable, Sendable {
    case saveTapped
    case saveSucceeded
    case saveFailed
    case retry
    case discard
}

public enum ReleaseSaveFlow {
    public static func nextState(from state: ReleaseSaveFlowState, event: ReleaseSaveFlowEvent) -> ReleaseSaveFlowState? {
        switch (state, event) {
        case (.review, .saveTapped), (.failed, .retry):
            return .saving
        case (.saving, .saveSucceeded):
            return .saved
        case (.saving, .saveFailed):
            return .failed
        case (.review, .discard), (.failed, .discard):
            return .discarded
        default:
            return nil
        }
    }
}
