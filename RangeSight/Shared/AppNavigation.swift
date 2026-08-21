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
    case monitoring
    case reviewing
    case saved
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
                AppAction(title: "Lock Target", destination: .liveMonitor),
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
                AppAction(title: "End String", destination: .stringReview),
                AppAction(title: "Pause", destination: .cameraSetup)
            ]
        ),
        AppScreen(
            id: .stringReview,
            title: "String Review",
            phase: .reviewing,
            description: "Correct impacts, confirm ambiguous candidates, and recalculate group and score summaries.",
            previewStatus: "Corrections enabled",
            actions: [
                AppAction(title: "Save String", destination: .sessionSummary),
                AppAction(title: "Monitor Again", destination: .liveMonitor)
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
                AppAction(title: "Home", destination: .home),
                AppAction(title: "Settings", destination: .settings)
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
