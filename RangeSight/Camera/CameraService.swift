@preconcurrency import AVFoundation

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
