@preconcurrency import AVFoundation
import Foundation

public enum LiveCameraFrameConversionError: Error, Equatable, Sendable {
    case unsupportedPixelFormat
    case invalidPlane
    case invalidDimensions
}

public enum LiveCameraFrameConverter {
    public static func luminanceFrame(from pixelBuffer: CVPixelBuffer) throws -> LuminanceFrame {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else {
            throw LiveCameraFrameConversionError.invalidDimensions
        }

        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        switch pixelFormat {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            guard CVPixelBufferGetPlaneCount(pixelBuffer) >= 1,
                  let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
                throw LiveCameraFrameConversionError.invalidPlane
            }

            let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
            var pixels: [Double] = []
            pixels.reserveCapacity(width * height)

            for y in 0..<height {
                let row = buffer.advanced(by: y * bytesPerRow)
                for x in 0..<width {
                    pixels.append(Double(row[x]) / 255.0)
                }
            }

            return try LuminanceFrame(width: width, height: height, pixels: pixels)

        case kCVPixelFormatType_32BGRA:
            guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
                throw LiveCameraFrameConversionError.invalidPlane
            }

            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
            var pixels: [Double] = []
            pixels.reserveCapacity(width * height)

            for y in 0..<height {
                let row = buffer.advanced(by: y * bytesPerRow)
                for x in 0..<width {
                    let offset = x * 4
                    let blue = Double(row[offset])
                    let green = Double(row[offset + 1])
                    let red = Double(row[offset + 2])
                    pixels.append((0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255.0)
                }
            }

            return try LuminanceFrame(width: width, height: height, pixels: pixels)

        default:
            throw LiveCameraFrameConversionError.unsupportedPixelFormat
        }
    }
}

public final class CameraPreviewSession: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    public let captureSession: AVCaptureSession
    private let sessionQueue: DispatchQueue
    private let analysisQueue: DispatchQueue
    private let videoOutput = AVCaptureVideoDataOutput()
    private var isConfigured = false
    private var liveFrameHandler: (@Sendable (VisionFrame) -> Void)?
    private var liveAnalysisConfiguration: LiveAnalysisConfiguration = .default
    private var analysisSequenceIndex = 0
    private var capturedFrameCount = 0
    private var analyzedFrameCount = 0
    private var droppedAnalysisFrameCount = 0
    private var totalProcessingDuration: TimeInterval = 0
    private var lastDeliveredTimestamp: TimeInterval?

    public init(
        captureSession: AVCaptureSession = AVCaptureSession(),
        sessionQueue: DispatchQueue = DispatchQueue(label: "com.rangesight.camera.preview"),
        analysisQueue: DispatchQueue = DispatchQueue(label: "com.rangesight.camera.analysis")
    ) {
        self.captureSession = captureSession
        self.sessionQueue = sessionQueue
        self.analysisQueue = analysisQueue
        super.init()
    }

    public func configureForPreview(
        deliversAnalysisFrames: Bool = false,
        _ completion: @escaping @Sendable (Result<Void, CameraSessionFailure>) -> Void
    ) {
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

                if deliversAnalysisFrames {
                    self.videoOutput.alwaysDiscardsLateVideoFrames = true
                    self.videoOutput.videoSettings = [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                    ]

                    guard captureSession.canAddOutput(self.videoOutput) else {
                        completion(.failure(.cannotAddOutput))
                        return
                    }

                    captureSession.addOutput(self.videoOutput)
                    self.videoOutput.setSampleBufferDelegate(self, queue: self.analysisQueue)
                }

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

    public func setLiveFrameHandler(_ handler: (@Sendable (VisionFrame) -> Void)?) {
        sessionQueue.async {
            self.liveFrameHandler = handler
        }
    }

    public func setLiveAnalysisConfiguration(_ configuration: LiveAnalysisConfiguration) {
        sessionQueue.async {
            self.liveAnalysisConfiguration = configuration
        }
    }

    public func liveAnalysisDiagnostics() -> LiveAnalysisDiagnostics {
        LiveAnalysisDiagnostics(
            capturedFrameCount: capturedFrameCount,
            analyzedFrameCount: analyzedFrameCount,
            droppedAnalysisFrameCount: droppedAnalysisFrameCount,
            inFlightTaskCount: 0,
            averageProcessingDuration: analyzedFrameCount > 0 ? totalProcessingDuration / Double(analyzedFrameCount) : 0,
            registrationFailureCount: 0
        )
    }

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        do {
            let processingStart = CFAbsoluteTimeGetCurrent()
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            capturedFrameCount += 1

            if liveAnalysisConfiguration.allowsStaleFrameDropping,
               let lastDeliveredTimestamp,
               timestamp.isFinite,
               timestamp - lastDeliveredTimestamp < liveAnalysisConfiguration.minimumFrameInterval {
                droppedAnalysisFrameCount += 1
                return
            }

            let luminance = try LiveCameraFrameConverter.luminanceFrame(from: imageBuffer)
            let frame = try VisionFrame(
                sequenceIndex: analysisSequenceIndex,
                timestamp: timestamp.isFinite && timestamp >= 0 ? timestamp : 0,
                dimensions: try FrameDimensions(width: luminance.width, height: luminance.height),
                orientation: .portrait,
                content: .fixtureLuminance(luminance)
            )
            analysisSequenceIndex += 1
            analyzedFrameCount += 1
            totalProcessingDuration += CFAbsoluteTimeGetCurrent() - processingStart
            lastDeliveredTimestamp = frame.timestamp
            liveFrameHandler?(frame)
        } catch {
            return
        }
    }

    private static func preferredBackCamera() -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }
}
