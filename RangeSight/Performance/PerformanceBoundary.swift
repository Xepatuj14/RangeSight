import Foundation

public struct LivePerformanceConfiguration: Codable, Equatable, Sendable {
    public static let defaultMinimumROIDimensions = try! FrameDimensions(width: 96, height: 96)

    public let targetPreviewResponsivenessFPS: Double
    public let nominalAnalysisCadence: TimeInterval
    public let seriousThermalAnalysisCadence: TimeInterval
    public let lowPowerAnalysisCadence: TimeInterval
    public let maximumInFlightAnalysisCount: Int
    public let frameQueueDepth: Int
    public let averageProcessingLatencyBudget: TimeInterval
    public let worstCaseProcessingLatencyBudget: TimeInterval
    public let rollingWindowSize: Int
    public let minimumROIDimensions: FrameDimensions
    public let downsampleFactor: Int

    public init(
        targetPreviewResponsivenessFPS: Double = 30,
        nominalAnalysisCadence: TimeInterval = 0.1,
        seriousThermalAnalysisCadence: TimeInterval = 0.25,
        lowPowerAnalysisCadence: TimeInterval = 0.2,
        maximumInFlightAnalysisCount: Int = 1,
        frameQueueDepth: Int = 1,
        averageProcessingLatencyBudget: TimeInterval = 0.08,
        worstCaseProcessingLatencyBudget: TimeInterval = 0.25,
        rollingWindowSize: Int = 60,
        minimumROIDimensions: FrameDimensions = LivePerformanceConfiguration.defaultMinimumROIDimensions,
        downsampleFactor: Int = 1
    ) throws {
        guard targetPreviewResponsivenessFPS > 0,
              nominalAnalysisCadence > 0,
              seriousThermalAnalysisCadence >= nominalAnalysisCadence,
              lowPowerAnalysisCadence >= nominalAnalysisCadence,
              maximumInFlightAnalysisCount > 0,
              frameQueueDepth > 0,
              averageProcessingLatencyBudget > 0,
              worstCaseProcessingLatencyBudget >= averageProcessingLatencyBudget,
              rollingWindowSize > 0,
              downsampleFactor > 0 else {
            throw PerformanceValidationError.invalidConfiguration
        }

        self.targetPreviewResponsivenessFPS = targetPreviewResponsivenessFPS
        self.nominalAnalysisCadence = nominalAnalysisCadence
        self.seriousThermalAnalysisCadence = seriousThermalAnalysisCadence
        self.lowPowerAnalysisCadence = lowPowerAnalysisCadence
        self.maximumInFlightAnalysisCount = maximumInFlightAnalysisCount
        self.frameQueueDepth = frameQueueDepth
        self.averageProcessingLatencyBudget = averageProcessingLatencyBudget
        self.worstCaseProcessingLatencyBudget = worstCaseProcessingLatencyBudget
        self.rollingWindowSize = rollingWindowSize
        self.minimumROIDimensions = minimumROIDimensions
        self.downsampleFactor = downsampleFactor
    }

    public static let `default` = try! LivePerformanceConfiguration()
}

public struct PixelRegion: Codable, Equatable, Hashable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) throws {
        guard x >= 0, y >= 0, width > 0, height > 0 else {
            throw PerformanceValidationError.invalidROI
        }

        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxXExclusive: Int {
        x + width
    }

    public var maxYExclusive: Int {
        y + height
    }

    public func contains(x pixelX: Int, y pixelY: Int) -> Bool {
        pixelX >= x && pixelX < maxXExclusive && pixelY >= y && pixelY < maxYExclusive
    }
}

public enum ROIExtractionStatus: String, Codable, Equatable, Sendable {
    case fullFrame
    case croppedROI
    case invalidROI
    case targetTooSmallForReliableAnalysis
}

public struct ROIExtractionResult: Codable, Equatable, Sendable {
    public let status: ROIExtractionStatus
    public let region: PixelRegion?
    public let frame: LuminanceFrame?

    public init(status: ROIExtractionStatus, region: PixelRegion?, frame: LuminanceFrame?) {
        self.status = status
        self.region = region
        self.frame = frame
    }
}

public enum TargetROIMapper {
    public static func pixelRegion(
        for quadrilateral: TargetQuadrilateral,
        sourceDimensions: FrameDimensions,
        minimumDimensions: FrameDimensions,
        normalizedMargin: Double = 0
    ) throws -> PixelRegion {
        guard normalizedMargin >= 0, normalizedMargin.isFinite else {
            throw PerformanceValidationError.invalidROI
        }

        let xs = quadrilateral.corners.map(\.x)
        let ys = quadrilateral.corners.map(\.y)
        guard let minX = xs.min(),
              let maxX = xs.max(),
              let minY = ys.min(),
              let maxY = ys.max(),
              minX >= 0,
              minY >= 0,
              maxX <= 1,
              maxY <= 1,
              maxX > minX,
              maxY > minY else {
            throw PerformanceValidationError.invalidROI
        }

        let paddedMinX = max(0, minX - normalizedMargin)
        let paddedMinY = max(0, minY - normalizedMargin)
        let paddedMaxX = min(1, maxX + normalizedMargin)
        let paddedMaxY = min(1, maxY + normalizedMargin)

        let pixelMinX = Int((paddedMinX * Double(sourceDimensions.width)).rounded(.down))
        let pixelMinY = Int((paddedMinY * Double(sourceDimensions.height)).rounded(.down))
        let pixelMaxX = Int((paddedMaxX * Double(sourceDimensions.width)).rounded(.up))
        let pixelMaxY = Int((paddedMaxY * Double(sourceDimensions.height)).rounded(.up))

        guard pixelMinX >= 0,
              pixelMinY >= 0,
              pixelMaxX <= sourceDimensions.width,
              pixelMaxY <= sourceDimensions.height else {
            throw PerformanceValidationError.invalidROI
        }

        let region = try PixelRegion(
            x: pixelMinX,
            y: pixelMinY,
            width: pixelMaxX - pixelMinX,
            height: pixelMaxY - pixelMinY
        )

        guard region.width >= minimumDimensions.width,
              region.height >= minimumDimensions.height else {
            throw PerformanceValidationError.targetTooSmallForReliableAnalysis
        }

        return region
    }

    public static func sourcePoint(
        fromROILocalPoint point: NormalizedImagePoint,
        region: PixelRegion,
        sourceDimensions: FrameDimensions
    ) throws -> NormalizedImagePoint {
        guard region.maxXExclusive <= sourceDimensions.width,
              region.maxYExclusive <= sourceDimensions.height else {
            throw PerformanceValidationError.invalidROI
        }

        let sourceX = (Double(region.x) + point.x * Double(region.width)) / Double(sourceDimensions.width)
        let sourceY = (Double(region.y) + point.y * Double(region.height)) / Double(sourceDimensions.height)
        return try NormalizedImagePoint(x: sourceX, y: sourceY)
    }
}

public enum LuminanceROIExtractor {
    public static func extract(
        from frame: LuminanceFrame,
        region: PixelRegion?,
        minimumDimensions: FrameDimensions,
        downsampleFactor: Int = 1
    ) throws -> ROIExtractionResult {
        guard downsampleFactor > 0 else {
            throw PerformanceValidationError.invalidConfiguration
        }

        guard let region else {
            return ROIExtractionResult(status: .fullFrame, region: nil, frame: frame)
        }

        guard region.x >= 0,
              region.y >= 0,
              region.maxXExclusive <= frame.width,
              region.maxYExclusive <= frame.height else {
            throw PerformanceValidationError.invalidROI
        }

        guard region.width >= minimumDimensions.width,
              region.height >= minimumDimensions.height else {
            throw PerformanceValidationError.targetTooSmallForReliableAnalysis
        }

        let outputWidth = max(1, region.width / downsampleFactor)
        let outputHeight = max(1, region.height / downsampleFactor)
        var pixels: [Double] = []
        pixels.reserveCapacity(outputWidth * outputHeight)

        for outputY in 0..<outputHeight {
            let sourceY = min(region.y + outputY * downsampleFactor, region.maxYExclusive - 1)
            for outputX in 0..<outputWidth {
                let sourceX = min(region.x + outputX * downsampleFactor, region.maxXExclusive - 1)
                pixels.append(frame.luminanceAt(x: sourceX, y: sourceY))
            }
        }

        return ROIExtractionResult(
            status: .croppedROI,
            region: region,
            frame: try LuminanceFrame(width: outputWidth, height: outputHeight, pixels: pixels)
        )
    }
}

public enum FrameDropReason: String, Codable, Equatable, Sendable {
    case cadence
    case backpressure
    case invalidROI
    case registrationRejected
    case globalChangeRejected
    case sessionEnded
}

public struct DroppedFrameCounters: Codable, Equatable, Sendable {
    public private(set) var cadenceDroppedFrameCount: Int
    public private(set) var backpressureDroppedFrameCount: Int
    public private(set) var invalidROIFrameCount: Int
    public private(set) var registrationRejectedFrameCount: Int
    public private(set) var globalChangeRejectedFrameCount: Int
    public private(set) var sessionEndedDroppedFrameCount: Int

    public init(
        cadenceDroppedFrameCount: Int = 0,
        backpressureDroppedFrameCount: Int = 0,
        invalidROIFrameCount: Int = 0,
        registrationRejectedFrameCount: Int = 0,
        globalChangeRejectedFrameCount: Int = 0,
        sessionEndedDroppedFrameCount: Int = 0
    ) {
        self.cadenceDroppedFrameCount = cadenceDroppedFrameCount
        self.backpressureDroppedFrameCount = backpressureDroppedFrameCount
        self.invalidROIFrameCount = invalidROIFrameCount
        self.registrationRejectedFrameCount = registrationRejectedFrameCount
        self.globalChangeRejectedFrameCount = globalChangeRejectedFrameCount
        self.sessionEndedDroppedFrameCount = sessionEndedDroppedFrameCount
    }

    public var totalDroppedFrameCount: Int {
        cadenceDroppedFrameCount +
        backpressureDroppedFrameCount +
        invalidROIFrameCount +
        registrationRejectedFrameCount +
        globalChangeRejectedFrameCount +
        sessionEndedDroppedFrameCount
    }

    public mutating func record(_ reason: FrameDropReason) {
        switch reason {
        case .cadence:
            cadenceDroppedFrameCount += 1
        case .backpressure:
            backpressureDroppedFrameCount += 1
        case .invalidROI:
            invalidROIFrameCount += 1
        case .registrationRejected:
            registrationRejectedFrameCount += 1
        case .globalChangeRejected:
            globalChangeRejectedFrameCount += 1
        case .sessionEnded:
            sessionEndedDroppedFrameCount += 1
        }
    }
}

public struct AnalysisSchedulingDecision: Codable, Equatable, Sendable {
    public let shouldAnalyze: Bool
    public let dropReason: FrameDropReason?

    public static let analyze = AnalysisSchedulingDecision(shouldAnalyze: true, dropReason: nil)

    public static func drop(_ reason: FrameDropReason) -> AnalysisSchedulingDecision {
        AnalysisSchedulingDecision(shouldAnalyze: false, dropReason: reason)
    }
}

public struct LiveAnalysisScheduler: Codable, Equatable, Sendable {
    public private(set) var capturedFrameCount: Int = 0
    public private(set) var analyzedFrameCount: Int = 0
    public private(set) var inFlightAnalysisCount: Int = 0
    public private(set) var lastAcceptedTimestamp: TimeInterval?
    public private(set) var dropCounters = DroppedFrameCounters()
    private let configuration: LivePerformanceConfiguration

    public init(configuration: LivePerformanceConfiguration = .default) {
        self.configuration = configuration
    }

    public mutating func submitFrame(
        timestamp: TimeInterval,
        sessionActive: Bool = true,
        minimumFrameInterval: TimeInterval? = nil
    ) -> AnalysisSchedulingDecision {
        capturedFrameCount += 1

        guard sessionActive else {
            dropCounters.record(.sessionEnded)
            return .drop(.sessionEnded)
        }

        let requiredInterval = minimumFrameInterval ?? configuration.nominalAnalysisCadence
        if let lastAcceptedTimestamp,
           timestamp - lastAcceptedTimestamp < requiredInterval {
            dropCounters.record(.cadence)
            return .drop(.cadence)
        }

        guard inFlightAnalysisCount < configuration.maximumInFlightAnalysisCount else {
            dropCounters.record(.backpressure)
            return .drop(.backpressure)
        }

        inFlightAnalysisCount += 1
        lastAcceptedTimestamp = timestamp
        analyzedFrameCount += 1
        return .analyze
    }

    public mutating func finishFrame() {
        inFlightAnalysisCount = max(0, inFlightAnalysisCount - 1)
    }

    public mutating func recordDrop(_ reason: FrameDropReason) {
        dropCounters.record(reason)
    }

    public mutating func resetForSessionEnd() {
        inFlightAnalysisCount = 0
        lastAcceptedTimestamp = nil
    }
}

public enum PerformanceStage: String, Codable, CaseIterable, Equatable, Sendable {
    case pixelBufferROIConversion
    case registration
    case alignmentResampling
    case changeDetection
    case temporalConfirmation
    case totalAnalysis
}

public struct StageTimingSample: Codable, Equatable, Sendable {
    public let stage: PerformanceStage
    public let duration: TimeInterval

    public init(stage: PerformanceStage, duration: TimeInterval) throws {
        guard duration >= 0, duration.isFinite else {
            throw PerformanceValidationError.invalidTiming
        }

        self.stage = stage
        self.duration = duration
    }
}

public struct RollingPerformanceMetrics: Codable, Equatable, Sendable {
    public let capacity: Int
    private var samples: [StageTimingSample] = []
    public private(set) var analyzedFrameCount: Int = 0
    public private(set) var dropCounters = DroppedFrameCounters()

    public init(capacity: Int = LivePerformanceConfiguration.default.rollingWindowSize) throws {
        guard capacity > 0 else {
            throw PerformanceValidationError.invalidConfiguration
        }

        self.capacity = capacity
    }

    public var sampleCount: Int {
        samples.count
    }

    public var averageProcessingDuration: TimeInterval {
        averageDuration(for: .totalAnalysis)
    }

    public var rollingHighWaterDuration: TimeInterval {
        samples.map(\.duration).max() ?? 0
    }

    public mutating func record(_ sample: StageTimingSample) {
        samples.append(sample)
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }

        if sample.stage == .totalAnalysis {
            analyzedFrameCount += 1
        }
    }

    public mutating func recordDrop(_ reason: FrameDropReason) {
        dropCounters.record(reason)
    }

    public func averageDuration(for stage: PerformanceStage) -> TimeInterval {
        let stageSamples = samples.filter { $0.stage == stage }
        guard !stageSamples.isEmpty else {
            return 0
        }

        return stageSamples.map(\.duration).reduce(0, +) / Double(stageSamples.count)
    }
}

public enum DeviceThermalState: String, Codable, CaseIterable, Equatable, Sendable {
    case nominal
    case fair
    case serious
    case critical
}

public struct RuntimePowerState: Codable, Equatable, Sendable {
    public let thermalState: DeviceThermalState
    public let lowPowerModeEnabled: Bool

    public init(thermalState: DeviceThermalState, lowPowerModeEnabled: Bool) {
        self.thermalState = thermalState
        self.lowPowerModeEnabled = lowPowerModeEnabled
    }
}

public enum LivePerformanceMode: String, Codable, Equatable, Sendable {
    case normal
    case reducedCadence
    case reducedResolution
    case paused
}

public struct PerformancePolicyDecision: Codable, Equatable, Sendable {
    public let mode: LivePerformanceMode
    public let analysisCadence: TimeInterval
    public let userStatus: String?

    public init(mode: LivePerformanceMode, analysisCadence: TimeInterval, userStatus: String?) {
        self.mode = mode
        self.analysisCadence = analysisCadence
        self.userStatus = userStatus
    }
}

public enum ThermalPowerPolicy {
    public static func decision(
        for state: RuntimePowerState,
        configuration: LivePerformanceConfiguration = .default
    ) -> PerformancePolicyDecision {
        switch state.thermalState {
        case .critical:
            return PerformancePolicyDecision(
                mode: .paused,
                analysisCadence: configuration.seriousThermalAnalysisCadence,
                userStatus: "Device is too warm for reliable live analysis."
            )
        case .serious:
            return PerformancePolicyDecision(
                mode: .reducedResolution,
                analysisCadence: configuration.seriousThermalAnalysisCadence,
                userStatus: "Reduced analysis rate"
            )
        case .fair:
            return PerformancePolicyDecision(
                mode: state.lowPowerModeEnabled ? .reducedCadence : .normal,
                analysisCadence: state.lowPowerModeEnabled ? configuration.lowPowerAnalysisCadence : configuration.nominalAnalysisCadence,
                userStatus: state.lowPowerModeEnabled ? "Reduced analysis rate" : nil
            )
        case .nominal:
            return PerformancePolicyDecision(
                mode: state.lowPowerModeEnabled ? .reducedCadence : .normal,
                analysisCadence: state.lowPowerModeEnabled ? configuration.lowPowerAnalysisCadence : configuration.nominalAnalysisCadence,
                userStatus: state.lowPowerModeEnabled ? "Reduced analysis rate" : nil
            )
        }
    }
}

public enum CameraCapability: String, Codable, CaseIterable, Equatable, Sendable {
    case tripleCamera
    case dualWideCamera
    case wideAngleCamera
}

public enum AnalysisPixelFormat: String, Codable, CaseIterable, Equatable, Sendable {
    case yuvFullRange
    case yuvVideoRange
    case bgra
}

public struct DeviceCapabilityProfile: Codable, Equatable, Sendable {
    public let availableCameras: [CameraCapability]
    public let supportedPixelFormats: [AnalysisPixelFormat]
    public let supportedFrameDimensions: [FrameDimensions]
    public let runtimePowerState: RuntimePowerState

    public init(
        availableCameras: [CameraCapability],
        supportedPixelFormats: [AnalysisPixelFormat],
        supportedFrameDimensions: [FrameDimensions],
        runtimePowerState: RuntimePowerState = RuntimePowerState(thermalState: .nominal, lowPowerModeEnabled: false)
    ) {
        self.availableCameras = availableCameras
        self.supportedPixelFormats = supportedPixelFormats
        self.supportedFrameDimensions = supportedFrameDimensions
        self.runtimePowerState = runtimePowerState
    }
}

public enum DeviceFallbackStatus: Codable, Equatable, Sendable {
    case supported(camera: CameraCapability, pixelFormat: AnalysisPixelFormat, dimensions: FrameDimensions)
    case unsupported
}

public enum DeviceCapabilitySelector {
    public static func select(from profile: DeviceCapabilityProfile) -> DeviceFallbackStatus {
        guard let camera = [.tripleCamera, .dualWideCamera, .wideAngleCamera].first(where: {
            profile.availableCameras.contains($0)
        }),
              let pixelFormat = [.yuvFullRange, .yuvVideoRange, .bgra].first(where: {
                profile.supportedPixelFormats.contains($0)
              }),
              let dimensions = profile.supportedFrameDimensions.sorted(by: {
                ($0.width * $0.height) > ($1.width * $1.height)
              }).first else {
            return .unsupported
        }

        return .supported(camera: camera, pixelFormat: pixelFormat, dimensions: dimensions)
    }
}

public enum PerformanceValidationError: Error, Equatable {
    case invalidConfiguration
    case invalidROI
    case targetTooSmallForReliableAnalysis
    case invalidTiming
}
