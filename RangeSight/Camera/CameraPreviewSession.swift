@preconcurrency import AVFoundation
import Foundation

public enum LiveCameraFrameConversionError: Error, Equatable, Sendable {
    case unsupportedPixelFormat
    case invalidPlane
    case invalidDimensions
    case invalidROI
    case targetTooSmallForReliableAnalysis
}

public enum LiveCameraFrameConverter {
    public static func luminanceFrame(
        from pixelBuffer: CVPixelBuffer,
        region: PixelRegion? = nil,
        downsampleFactor: Int = 1
    ) throws -> LuminanceFrame {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0, downsampleFactor > 0 else {
            throw LiveCameraFrameConversionError.invalidDimensions
        }
        let sourceRegion = try validatedRegion(region, sourceWidth: width, sourceHeight: height)
        let outputWidth = max(1, sourceRegion.width / downsampleFactor)
        let outputHeight = max(1, sourceRegion.height / downsampleFactor)

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
            pixels.reserveCapacity(outputWidth * outputHeight)

            for outputY in 0..<outputHeight {
                let sourceY = min(sourceRegion.y + outputY * downsampleFactor, sourceRegion.maxYExclusive - 1)
                let row = buffer.advanced(by: sourceY * bytesPerRow)
                for outputX in 0..<outputWidth {
                    let sourceX = min(sourceRegion.x + outputX * downsampleFactor, sourceRegion.maxXExclusive - 1)
                    pixels.append(Double(row[sourceX]) / 255.0)
                }
            }

            return try LuminanceFrame(width: outputWidth, height: outputHeight, pixels: pixels)

        case kCVPixelFormatType_32BGRA:
            guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
                throw LiveCameraFrameConversionError.invalidPlane
            }

            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
            var pixels: [Double] = []
            pixels.reserveCapacity(outputWidth * outputHeight)

            for outputY in 0..<outputHeight {
                let sourceY = min(sourceRegion.y + outputY * downsampleFactor, sourceRegion.maxYExclusive - 1)
                let row = buffer.advanced(by: sourceY * bytesPerRow)
                for outputX in 0..<outputWidth {
                    let sourceX = min(sourceRegion.x + outputX * downsampleFactor, sourceRegion.maxXExclusive - 1)
                    let offset = sourceX * 4
                    let blue = Double(row[offset])
                    let green = Double(row[offset + 1])
                    let red = Double(row[offset + 2])
                    pixels.append((0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255.0)
                }
            }

            return try LuminanceFrame(width: outputWidth, height: outputHeight, pixels: pixels)

        default:
            throw LiveCameraFrameConversionError.unsupportedPixelFormat
        }
    }

    private static func validatedRegion(
        _ region: PixelRegion?,
        sourceWidth: Int,
        sourceHeight: Int
    ) throws -> PixelRegion {
        guard let region else {
            return try PixelRegion(x: 0, y: 0, width: sourceWidth, height: sourceHeight)
        }

        guard region.x >= 0,
              region.y >= 0,
              region.maxXExclusive <= sourceWidth,
              region.maxYExclusive <= sourceHeight else {
            throw LiveCameraFrameConversionError.invalidROI
        }

        return region
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
    private var performanceConfiguration: LivePerformanceConfiguration = .default
    private var targetLockAssessment: TargetLockAssessment?
    private var scheduler = LiveAnalysisScheduler()
    private var rollingMetrics: RollingPerformanceMetrics?
    private var analysisSequenceIndex = 0
    private var capturedFrameCount = 0
    private var analyzedFrameCount = 0
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

    public func setLivePerformanceConfiguration(_ configuration: LivePerformanceConfiguration) {
        sessionQueue.async {
            self.performanceConfiguration = configuration
            self.scheduler = LiveAnalysisScheduler(configuration: configuration)
            self.rollingMetrics = try? RollingPerformanceMetrics(capacity: configuration.rollingWindowSize)
        }
    }

    public func setTargetLockAssessment(_ assessment: TargetLockAssessment?) {
        sessionQueue.async {
            self.targetLockAssessment = assessment
        }
    }

    public func endLiveAnalysisSession() {
        sessionQueue.async {
            self.scheduler.resetForSessionEnd()
            self.lastDeliveredTimestamp = nil
        }
    }

    public func liveAnalysisDiagnostics() -> LiveAnalysisDiagnostics {
        LiveAnalysisDiagnostics(
            capturedFrameCount: capturedFrameCount,
            analyzedFrameCount: analyzedFrameCount,
            droppedAnalysisFrameCount: scheduler.dropCounters.totalDroppedFrameCount,
            inFlightTaskCount: scheduler.inFlightAnalysisCount,
            averageProcessingDuration: rollingMetrics?.averageProcessingDuration ?? 0,
            registrationFailureCount: scheduler.dropCounters.registrationRejectedFrameCount,
            cadenceDroppedFrameCount: scheduler.dropCounters.cadenceDroppedFrameCount,
            backpressureDroppedFrameCount: scheduler.dropCounters.backpressureDroppedFrameCount,
            invalidROIFrameCount: scheduler.dropCounters.invalidROIFrameCount,
            globalChangeRejectedFrameCount: scheduler.dropCounters.globalChangeRejectedFrameCount,
            rollingHighWaterProcessingDuration: rollingMetrics?.rollingHighWaterDuration ?? 0
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
            let powerDecision = ThermalPowerPolicy.decision(
                for: RuntimePowerState(
                    thermalState: Self.currentThermalState(),
                    lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
                ),
                configuration: performanceConfiguration
            )
            guard powerDecision.mode != .paused else {
                scheduler.recordDrop(.backpressure)
                return
            }
            let cadence = max(liveAnalysisConfiguration.minimumFrameInterval, powerDecision.analysisCadence)
            let decision = scheduler.submitFrame(
                timestamp: timestamp.isFinite ? timestamp : 0,
                minimumFrameInterval: liveAnalysisConfiguration.allowsStaleFrameDropping ? cadence : 0
            )
            guard decision.shouldAnalyze else {
                return
            }
            defer {
                scheduler.finishFrame()
            }

            let sourceDimensions = try FrameDimensions(
                width: CVPixelBufferGetWidth(imageBuffer),
                height: CVPixelBufferGetHeight(imageBuffer)
            )
            let region = try targetROIRegion(sourceDimensions: sourceDimensions)
            let luminance = try LiveCameraFrameConverter.luminanceFrame(
                from: imageBuffer,
                region: region,
                downsampleFactor: powerDecision.mode == .reducedResolution ? max(1, performanceConfiguration.downsampleFactor) : 1
            )
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
            if rollingMetrics == nil {
                rollingMetrics = try? RollingPerformanceMetrics(capacity: performanceConfiguration.rollingWindowSize)
            }
            rollingMetrics?.record(
                try StageTimingSample(
                    stage: .pixelBufferROIConversion,
                    duration: CFAbsoluteTimeGetCurrent() - processingStart
                )
            )
            rollingMetrics?.record(
                try StageTimingSample(
                    stage: .totalAnalysis,
                    duration: CFAbsoluteTimeGetCurrent() - processingStart
                )
            )
            lastDeliveredTimestamp = frame.timestamp
            liveFrameHandler?(frame)
        } catch LiveCameraFrameConversionError.invalidROI,
                PerformanceValidationError.invalidROI,
                PerformanceValidationError.targetTooSmallForReliableAnalysis,
                LiveCameraFrameConversionError.targetTooSmallForReliableAnalysis {
            scheduler.recordDrop(.invalidROI)
            return
        } catch {
            return
        }
    }

    private func targetROIRegion(sourceDimensions: FrameDimensions) throws -> PixelRegion? {
        guard let targetLockAssessment else {
            return nil
        }

        guard targetLockAssessment.canLock else {
            throw PerformanceValidationError.invalidROI
        }

        return try TargetROIMapper.pixelRegion(
            for: targetLockAssessment.quadrilateral,
            sourceDimensions: sourceDimensions,
            minimumDimensions: performanceConfiguration.minimumROIDimensions
        )
    }

    private static func preferredBackCamera() -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    private static func currentThermalState() -> DeviceThermalState {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            return .nominal
        case .fair:
            return .fair
        case .serious:
            return .serious
        case .critical:
            return .critical
        @unknown default:
            return .serious
        }
    }
}
