public enum RangeSessionState: String, CaseIterable, Sendable {
    case idle
    case setup
    case preview
    case locked
    case monitoring
    case paused
    case reviewing
    case saved
}

public enum RangeSessionEvent: String, Sendable {
    case beginSetup
    case startPreview
    case lockTarget
    case startString
    case pause
    case resume
    case endString
    case save
    case reset
}

public enum SessionStateMachine {
    public static func nextState(from state: RangeSessionState, event: RangeSessionEvent) -> RangeSessionState? {
        switch (state, event) {
        case (.idle, .beginSetup):
            return .setup
        case (.setup, .startPreview):
            return .preview
        case (.preview, .lockTarget):
            return .locked
        case (.locked, .startString):
            return .monitoring
        case (.monitoring, .pause):
            return .paused
        case (.paused, .resume):
            return .monitoring
        case (.monitoring, .endString), (.paused, .endString):
            return .reviewing
        case (.reviewing, .save):
            return .saved
        case (_, .reset):
            return .idle
        default:
            return nil
        }
    }
}
