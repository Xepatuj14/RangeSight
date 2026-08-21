import AVFoundation
import SwiftUI
import UIKit
import RangeSightCore

@MainActor
final class CameraPreviewModel: ObservableObject {
    @Published private(set) var authorizationState: CameraAuthorizationState = .notDetermined
    @Published private(set) var sessionState: CameraSessionState = .idle

    let previewSession: CameraPreviewSession
    private let cameraService: any CameraService
    private var activationTask: Task<Void, Never>?
    private var startupTimeoutTask: Task<Void, Never>?
    private var activationGeneration = 0

    init(
        cameraService: any CameraService = AVCaptureCameraService(),
        previewSession: CameraPreviewSession = CameraPreviewSession()
    ) {
        self.cameraService = cameraService
        self.previewSession = previewSession
    }

    func activate() {
        activationGeneration += 1
        let generation = activationGeneration
        activationTask?.cancel()
        startupTimeoutTask?.cancel()
        sessionState = .idle

        activationTask = Task { [weak self] in
            guard let self else { return }
            let state = await cameraService.authorizationState()
            guard !Task.isCancelled, generation == activationGeneration else { return }

            if state == .notDetermined {
                authorizationState = await cameraService.requestAuthorization()
            } else {
                authorizationState = state
            }
            guard !Task.isCancelled, generation == activationGeneration else { return }

            guard authorizationState == .authorized else {
                sessionState = .failed(.cameraUnavailable)
                return
            }

            sessionState = .configuring
            scheduleStartupTimeout(for: generation)
            previewSession.configureForPreview { [weak self] result in
                Task { @MainActor in
                    guard let self,
                          generation == self.activationGeneration else {
                        return
                    }

                    self.startupTimeoutTask?.cancel()
                    switch result {
                    case .success:
                        self.sessionState = .running
                        self.previewSession.start()
                    case .failure(let failure):
                        self.sessionState = .failed(failure)
                    }
                }
            }
        }
    }

    func deactivate() {
        activationGeneration += 1
        activationTask?.cancel()
        startupTimeoutTask?.cancel()
        previewSession.stop()
        sessionState = .stopped
    }

    func retry() {
        deactivate()
        activate()
    }

    private func scheduleStartupTimeout(for generation: Int) {
        startupTimeoutTask?.cancel()
        let timeout = ReleaseTimeoutPolicy.cameraStartup.duration ?? 8
        let nanoseconds = UInt64(timeout * 1_000_000_000)
        startupTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }

            await MainActor.run {
                guard let self,
                      generation == self.activationGeneration,
                      self.sessionState == .configuring else {
                    return
                }

                self.previewSession.stop()
                self.sessionState = .failed(.startupTimedOut)
            }
        }
    }
}

struct CameraPreviewSurface: View {
    @StateObject private var model = CameraPreviewModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            PreviewLayerView(session: model.previewSession.captureSession)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .topLeading) {
                    statusBadge
                        .padding(12)
                }

            VStack(spacing: 4) {
                Text(statusText.uppercased())
                    .font(.caption.bold())
                if let recoveryText {
                    Text(recoveryText)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                if canRetryCamera {
                    Button("Retry Camera") {
                        model.retry()
                    }
                    .font(.caption.bold())
                    .buttonStyle(.borderedProminent)
                    .tint(.yellow)
                    .foregroundStyle(.black)
                    .padding(.top, 4)
                }
            }
            .foregroundStyle(.yellow)
            .padding(.bottom, 16)
        }
        .frame(minHeight: 360)
        .task {
            model.activate()
        }
        .onDisappear {
            model.deactivate()
        }
        .accessibilityLabel("Live camera preview")
    }

    private var statusBadge: some View {
        Label(statusText, systemImage: statusSymbol)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.black.opacity(0.72))
            .clipShape(Capsule())
    }

    private var statusText: String {
        switch (model.authorizationState, model.sessionState) {
        case (.denied, _), (.restricted, _):
            return "Camera permission required"
        case (_, .configuring):
            return "Starting camera"
        case (_, .running):
            return "Preview active"
        case (_, .failed):
            return "Camera needs attention"
        case (_, .stopped):
            return "Preview stopped"
        default:
            return "Camera preview"
        }
    }

    private var recoveryText: String? {
        switch model.authorizationState {
        case .denied, .restricted:
            return ReleasePermissionCopy.cameraMessage(for: model.authorizationState)
        default:
            if case .failed(let failure) = model.sessionState {
                return ReleasePermissionCopy.cameraSessionMessage(for: failure)
            }

            return nil
        }
    }

    private var canRetryCamera: Bool {
        model.authorizationState == .authorized && {
            if case .failed = model.sessionState {
                return true
            }

            return false
        }()
    }

    private var statusSymbol: String {
        switch model.sessionState {
        case .running:
            return "camera.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        default:
            return "camera"
        }
    }
}

private struct PreviewLayerView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
