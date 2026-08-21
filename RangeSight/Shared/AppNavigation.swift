public enum AppScreenID: String, CaseIterable, Sendable {
    case home
    case sessionSetup
    case cameraSetup
    case liveMonitor
    case stringReview
    case sessionSummary
    case history
    case firearmProfiles
    case settings
}

public enum SessionPhase: String, Sendable {
    case idle
    case setup
    case preview
    case ready
    case monitoring
    case paused
    case reviewing
    case saved
}

public enum RangeSightWorkflowRoute: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case home
    case sessionSetup
    case cameraSetup
    case ready
    case liveString
    case pausedString
    case stringReview
    case stringSummary
    case sessionSummary
    case history
    case historyDetail
    case settings
}

public enum RangeSightWorkflowExitPolicy: String, Codable, Equatable, Sendable {
    case normalBack
    case confirmEndOrContinue
    case confirmDiscardString
    case doneToHome
}

public enum RangeSightWorkflowEvent: String, Codable, Equatable, Sendable {
    case newSession
    case back
    case continueToCamera
    case lockTarget
    case relockTarget
    case startString
    case pause
    case resume
    case endString
    case saveString
    case shootAnotherString
    case endSession
    case done
    case openHistory
    case openHistoryDetail
    case openSettings
}

public enum SessionDraftValidationError: String, Error, Codable, Equatable, Sendable {
    case missingFirearm
    case missingTarget
    case invalidDistance
}

public struct SessionDraft: Codable, Equatable, Sendable {
    public let sessionID: RangeSessionID
    public var selectedFirearm: FirearmProfile?
    public var selectedTarget: TargetDefinition?
    public var distance: Double
    public var distanceUnit: DistanceUnit
    public var audioAssistEnabled: Bool
    public let createdAt: Date
    public var targetLockedAt: Date?

    public init(
        sessionID: RangeSessionID,
        selectedFirearm: FirearmProfile? = nil,
        selectedTarget: TargetDefinition? = SupportedTargetCatalog.allTargetDefinitions.first,
        distance: Double = 10,
        distanceUnit: DistanceUnit = .yard,
        audioAssistEnabled: Bool = false,
        createdAt: Date,
        targetLockedAt: Date? = nil
    ) {
        self.sessionID = sessionID
        self.selectedFirearm = selectedFirearm
        self.selectedTarget = selectedTarget
        self.distance = distance
        self.distanceUnit = distanceUnit
        self.audioAssistEnabled = audioAssistEnabled
        self.createdAt = createdAt
        self.targetLockedAt = targetLockedAt
    }

    public var validationErrors: [SessionDraftValidationError] {
        var errors: [SessionDraftValidationError] = []
        if selectedFirearm == nil {
            errors.append(.missingFirearm)
        }
        if selectedTarget == nil {
            errors.append(.missingTarget)
        }
        if !Self.isValidDistance(distance) {
            errors.append(.invalidDistance)
        }
        return errors
    }

    public var isValidForCameraSetup: Bool {
        validationErrors.isEmpty
    }

    public mutating func selectDistance(_ distance: Double, unit: DistanceUnit = .yard) throws {
        guard Self.isValidDistance(distance) else {
            throw SessionDraftValidationError.invalidDistance
        }
        self.distance = distance
        self.distanceUnit = unit
    }

    public static func isValidDistance(_ distance: Double) -> Bool {
        distance.isFinite && (1...100).contains(distance)
    }
}

public struct SavedStringSummary: Codable, Equatable, Sendable, Identifiable {
    public let id: RangeStringID
    public let index: Int
    public let acceptedShotCount: Int
    public let totalScore: Double?

    public init(id: RangeStringID, index: Int, acceptedShotCount: Int, totalScore: Double?) {
        self.id = id
        self.index = index
        self.acceptedShotCount = acceptedShotCount
        self.totalScore = totalScore
    }
}

public struct RangeSightWorkflow: Equatable, Sendable {
    public private(set) var route: RangeSightWorkflowRoute
    public private(set) var domainState: RangeSessionState
    public private(set) var draft: SessionDraft?
    public private(set) var activeStringID: RangeStringID?
    public private(set) var activeStringIndex: Int
    public private(set) var savedStrings: [SavedStringSummary]
    public private(set) var hasUnsavedReviewChanges: Bool

    public init() {
        self.route = .home
        self.domainState = .idle
        self.draft = nil
        self.activeStringID = nil
        self.activeStringIndex = 0
        self.savedStrings = []
        self.hasUnsavedReviewChanges = false
    }

    public var exitPolicy: RangeSightWorkflowExitPolicy {
        switch route {
        case .liveString, .pausedString:
            return .confirmEndOrContinue
        case .stringReview where hasUnsavedReviewChanges:
            return .confirmDiscardString
        case .sessionSummary:
            return .doneToHome
        default:
            return .normalBack
        }
    }

    public mutating func beginNewSession(
        sessionID: RangeSessionID,
        createdAt: Date,
        target: TargetDefinition? = SupportedTargetCatalog.allTargetDefinitions.first
    ) {
        draft = SessionDraft(sessionID: sessionID, selectedTarget: target, createdAt: createdAt)
        activeStringID = nil
        activeStringIndex = 0
        savedStrings = []
        hasUnsavedReviewChanges = false
        domainState = SessionStateMachine.nextState(from: .idle, event: .beginSetup) ?? .setup
        route = .sessionSetup
    }

    public mutating func continueToCamera() throws {
        guard let draft, draft.isValidForCameraSetup else {
            throw draft?.validationErrors.first ?? SessionDraftValidationError.missingFirearm
        }
        guard let nextState = SessionStateMachine.nextState(from: domainState, event: .startPreview) else {
            return
        }
        domainState = nextState
        route = .cameraSetup
    }

    public mutating func selectFirearm(_ firearm: FirearmProfile) {
        draft?.selectedFirearm = firearm
    }

    public mutating func selectTarget(_ target: TargetDefinition) {
        draft?.selectedTarget = target
    }

    public mutating func selectDistance(_ distance: Double, unit: DistanceUnit = .yard) throws {
        try draft?.selectDistance(distance, unit: unit)
    }

    public mutating func setAudioAssistEnabled(_ isEnabled: Bool) {
        draft?.audioAssistEnabled = isEnabled
    }

    public mutating func lockTarget(at date: Date) {
        guard let nextState = SessionStateMachine.nextState(from: domainState, event: .lockTarget) else {
            return
        }
        draft?.targetLockedAt = date
        domainState = nextState
        route = .ready
    }

    public mutating func startString(id: RangeStringID) {
        guard let nextState = SessionStateMachine.nextState(from: domainState, event: .startString) else {
            return
        }
        activeStringIndex += 1
        activeStringID = id
        hasUnsavedReviewChanges = true
        domainState = nextState
        route = .liveString
    }

    public mutating func pause() {
        guard let nextState = SessionStateMachine.nextState(from: domainState, event: .pause) else {
            return
        }
        domainState = nextState
        route = .pausedString
    }

    public mutating func resume() {
        guard let nextState = SessionStateMachine.nextState(from: domainState, event: .resume) else {
            return
        }
        domainState = nextState
        route = .liveString
    }

    public mutating func endString() {
        guard let nextState = SessionStateMachine.nextState(from: domainState, event: .endString) else {
            return
        }
        domainState = nextState
        route = .stringReview
    }

    public mutating func markReviewChanged() {
        if route == .stringReview {
            hasUnsavedReviewChanges = true
        }
    }

    public mutating func saveString(_ summary: SavedStringSummary) {
        guard let nextState = SessionStateMachine.nextState(from: domainState, event: .save) else {
            return
        }
        savedStrings.append(summary)
        hasUnsavedReviewChanges = false
        domainState = nextState
        route = .stringSummary
    }

    public mutating func shootAnotherString() {
        guard draft != nil else {
            return
        }
        activeStringID = nil
        hasUnsavedReviewChanges = false
        domainState = .locked
        route = .ready
    }

    public mutating func endSession() {
        route = .sessionSummary
    }

    public mutating func done() {
        self = RangeSightWorkflow()
    }

    public mutating func discardStringToCamera() {
        activeStringID = nil
        hasUnsavedReviewChanges = false
        domainState = .preview
        route = .cameraSetup
    }

    public mutating func back() {
        switch route {
        case .sessionSetup:
            done()
        case .cameraSetup:
            domainState = .setup
            route = .sessionSetup
        case .ready:
            domainState = .preview
            route = .cameraSetup
        case .historyDetail:
            route = .history
        case .history, .settings:
            route = .home
        default:
            break
        }
    }

    public mutating func openHistory() {
        route = .history
    }

    public mutating func openHistoryDetail() {
        route = .historyDetail
    }

    public mutating func openSettings() {
        route = .settings
    }
}

public struct AppAction: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let destination: AppScreenID

    public init(title: String, destination: AppScreenID) {
        self.id = "\(title)->\(destination.rawValue)"
        self.title = title
        self.destination = destination
    }
}

public struct AppScreen: Identifiable, Equatable, Sendable {
    public let id: AppScreenID
    public let title: String
    public let phase: SessionPhase
    public let description: String
    public let previewStatus: String
    public let actions: [AppAction]
}

public enum AppNavigation {
    public static let homeScreenID: AppScreenID = .home

    public static let screens: [AppScreen] = [
        AppScreen(
            id: .home,
            title: "Home",
            phase: .idle,
            description: "Start a new range session, resume recent work, or inspect saved history.",
            previewStatus: "No active session",
            actions: [
                AppAction(title: "New Session", destination: .sessionSetup),
                AppAction(title: "History", destination: .history)
            ]
        ),
        AppScreen(
            id: .sessionSetup,
            title: "Session Setup",
            phase: .setup,
            description: "Choose target family, distance, firearm profile, and range-session metadata.",
            previewStatus: "Setup required",
            actions: [
                AppAction(title: "Camera Setup", destination: .cameraSetup),
                AppAction(title: "Profiles", destination: .firearmProfiles)
            ]
        ),
        AppScreen(
            id: .cameraSetup,
            title: "Camera Setup",
            phase: .preview,
            description: "Frame the supported target and lock quality-controlled target geometry before monitoring.",
            previewStatus: "Target lock pending",
            actions: [
                AppAction(title: "Back to Setup", destination: .sessionSetup)
            ]
        ),
        AppScreen(
            id: .liveMonitor,
            title: "Live Monitor",
            phase: .monitoring,
            description: "Camera-first monitoring surface for confirmed impacts, warnings, and compact string metrics.",
            previewStatus: "Mock preview active",
            actions: [
                AppAction(title: "End String", destination: .stringReview)
            ]
        ),
        AppScreen(
            id: .stringReview,
            title: "String Review",
            phase: .reviewing,
            description: "Correct impacts, confirm ambiguous candidates, and recalculate group and score summaries.",
            previewStatus: "Corrections enabled",
            actions: [
                AppAction(title: "Save String", destination: .sessionSummary)
            ]
        ),
        AppScreen(
            id: .sessionSummary,
            title: "Session Summary",
            phase: .saved,
            description: "Review saved strings and session metadata before returning to the range workflow.",
            previewStatus: "Session saved locally",
            actions: [
                AppAction(title: "New String", destination: .cameraSetup),
                AppAction(title: "Home", destination: .home)
            ]
        ),
        AppScreen(
            id: .history,
            title: "History",
            phase: .saved,
            description: "Browse prior sessions by date, distance, target definition, and firearm profile.",
            previewStatus: "Local history",
            actions: [
                AppAction(title: "Home", destination: .home)
            ]
        ),
        AppScreen(
            id: .firearmProfiles,
            title: "Firearm Profiles",
            phase: .setup,
            description: "Maintain optional firearm metadata and defaults without making firearm-control claims.",
            previewStatus: "Optional metadata",
            actions: [
                AppAction(title: "Back to Setup", destination: .sessionSetup),
                AppAction(title: "Home", destination: .home)
            ]
        ),
        AppScreen(
            id: .settings,
            title: "Settings",
            phase: .idle,
            description: "Control audio, units, privacy, and debug retention defaults for the local-first app.",
            previewStatus: "Privacy first",
            actions: [
                AppAction(title: "Home", destination: .home)
            ]
        )
    ]

    public static func screen(for id: AppScreenID) -> AppScreen {
        guard let screen = screens.first(where: { $0.id == id }) else {
            return screens.first { $0.id == homeScreenID } ?? AppScreen(
                id: .home,
                title: "Home",
                phase: .idle,
                description: "Start a new range session or inspect saved history.",
                previewStatus: "No active session",
                actions: []
            )
        }
        return screen
    }

    public static func action(from source: AppScreenID, to destination: AppScreenID) -> AppAction? {
        screen(for: source).actions.first { $0.destination == destination }
    }
}
