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

public enum CameraSessionState: Equatable, Sendable {
    case idle
    case configuring
    case running
    case stopped
    case failed(CameraSessionFailure)
}

public enum CameraSessionFailure: Error, Equatable, Sendable {
    case cameraUnavailable
    case cannotAddInput
    case cannotAddOutput
}
