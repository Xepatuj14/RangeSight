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
}

public enum ReleaseHardeningValidationError: Error, Equatable {
    case invalidReleaseDefect
}
