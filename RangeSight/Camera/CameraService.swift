@preconcurrency import AVFoundation

public enum CameraAuthorizationState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

public protocol CameraService: Sendable {
    func authorizationState() async -> CameraAuthorizationState
    func requestAuthorization() async -> CameraAuthorizationState
}

public struct AVCaptureCameraService: CameraService {
    public init() {}

    public func authorizationState() async -> CameraAuthorizationState {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .restricted
        }
    }

    public func requestAuthorization() async -> CameraAuthorizationState {
        let granted = await AVCaptureDevice.requestAccess(for: .video)

        if granted {
            return .authorized
        }

        return await authorizationState()
    }
}
