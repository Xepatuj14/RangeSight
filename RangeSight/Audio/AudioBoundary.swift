public protocol AudioImpulseCandidateSource: Sendable {
    func isAvailable() async -> Bool
}
