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

    init(
        cameraService: any CameraService = AVCaptureCameraService(),
        previewSession: CameraPreviewSession = CameraPreviewSession()
    ) {
        self.cameraService = cameraService
        self.previewSession = previewSession
    }

    func activate() {
        Task {
            let state = await cameraService.authorizationState()

            if state == .notDetermined {
                authorizationState = await cameraService.requestAuthorization()
            } else {
                authorizationState = state
            }

            guard authorizationState == .authorized else {
                sessionState = .failed(.cameraUnavailable)
                return
            }

            sessionState = .configuring
            previewSession.configureForPreview { [weak self] result in
                Task { @MainActor in
                    switch result {
                    case .success:
                        self?.sessionState = .running
                        self?.previewSession.start()
                    case .failure(let failure):
                        self?.sessionState = .failed(failure)
                    }
                }
            }
        }
    }

    func deactivate() {
        previewSession.stop()
        sessionState = .stopped
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

            Text(statusText.uppercased())
                .font(.caption.bold())
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
            return "Camera unavailable"
        case (_, .stopped):
            return "Preview stopped"
        default:
            return "Camera preview"
        }
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
