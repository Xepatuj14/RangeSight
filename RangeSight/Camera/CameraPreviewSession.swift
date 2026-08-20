@preconcurrency import AVFoundation
import Foundation

public final class CameraPreviewSession: @unchecked Sendable {
    public let captureSession: AVCaptureSession
    private let sessionQueue: DispatchQueue
    private var isConfigured = false

    public init(
        captureSession: AVCaptureSession = AVCaptureSession(),
        sessionQueue: DispatchQueue = DispatchQueue(label: "com.rangesight.camera.preview")
    ) {
        self.captureSession = captureSession
        self.sessionQueue = sessionQueue
    }

    public func configureForPreview(_ completion: @escaping @Sendable (Result<Void, CameraSessionFailure>) -> Void) {
        sessionQueue.async { [captureSession] in
            if self.isConfigured {
                completion(.success(()))
                return
            }

            captureSession.beginConfiguration()
            captureSession.sessionPreset = .high
            defer {
                captureSession.commitConfiguration()
            }

            guard let camera = Self.preferredBackCamera() else {
                completion(.failure(.cameraUnavailable))
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: camera)

                guard captureSession.canAddInput(input) else {
                    completion(.failure(.cannotAddInput))
                    return
                }

                captureSession.addInput(input)
                self.isConfigured = true
                completion(.success(()))
            } catch {
                completion(.failure(.cameraUnavailable))
            }
        }
    }

    public func start() {
        sessionQueue.async { [captureSession] in
            guard !captureSession.isRunning else {
                return
            }

            captureSession.startRunning()
        }
    }

    public func stop() {
        sessionQueue.async { [captureSession] in
            guard captureSession.isRunning else {
                return
            }

            captureSession.stopRunning()
        }
    }

    private static func preferredBackCamera() -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }
}
