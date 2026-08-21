public protocol RangeSightRepository: Sendable {
    func loadStore() async throws -> PersistedRangeSightStore
    func replaceStore(_ store: PersistedRangeSightStore) async throws
    func upsertFirearmProfile(_ profile: FirearmProfile) async throws
    func upsertTargetDefinition(_ target: TargetDefinition) async throws
    func upsertRangeSession(_ session: RangeSession) async throws
    func rangeSession(id: RangeSessionID) async throws -> RangeSession?
    func rangeSessions() async throws -> [RangeSession]
    func upsertRangeString(_ rangeString: RangeString) async throws
    func rangeStrings(sessionID: RangeSessionID) async throws -> [RangeString]
    func upsertShot(_ shot: Shot) async throws
    func shots(stringID: RangeStringID) async throws -> [Shot]
    func replaceImpactCorrectionState(_ state: ImpactCorrectionState, stringID: RangeStringID) async throws
    func replaceImpactCorrectionHistory(_ impacts: [AcceptedImpact], stringID: RangeStringID) async throws
    func impactCorrectionHistory(stringID: RangeStringID) async throws -> [AcceptedImpact]
    func impactCorrectionState(stringID: RangeStringID) async throws -> ImpactCorrectionState
}
