import Foundation

public struct SessionSaveRequest: Equatable, Sendable {
    public let session: RangeSession
    public let rangeString: RangeString
    public let firearmProfile: FirearmProfile?
    public let targetDefinition: TargetDefinition
    public let correctionState: ImpactCorrectionState

    public init(
        session: RangeSession,
        rangeString: RangeString,
        firearmProfile: FirearmProfile? = nil,
        targetDefinition: TargetDefinition,
        correctionState: ImpactCorrectionState
    ) throws {
        guard rangeString.sessionID == session.id else {
            throw PersistenceError.missingRangeSession(rangeString.sessionID)
        }
        guard session.targetDefinitionID == targetDefinition.id else {
            throw DomainValidationError.invalidIdentifier("targetDefinitionID")
        }

        self.session = session
        self.rangeString = rangeString
        self.firearmProfile = firearmProfile
        self.targetDefinition = targetDefinition
        self.correctionState = correctionState
    }
}

public struct SessionSaveResult: Equatable, Sendable {
    public let sessionID: RangeSessionID
    public let stringID: RangeStringID
    public let acceptedShotCount: Int
    public let correctionHistoryCount: Int
    public let scoringResult: StringScoringResult

    public init(
        sessionID: RangeSessionID,
        stringID: RangeStringID,
        acceptedShotCount: Int,
        correctionHistoryCount: Int,
        scoringResult: StringScoringResult
    ) {
        self.sessionID = sessionID
        self.stringID = stringID
        self.acceptedShotCount = acceptedShotCount
        self.correctionHistoryCount = correctionHistoryCount
        self.scoringResult = scoringResult
    }
}

public struct ProductionSessionSaveCoordinator: Sendable {
    private let scoringEngine: AcceptedImpactStringScoringEngine

    public init(scoringEngine: AcceptedImpactStringScoringEngine = AcceptedImpactStringScoringEngine()) {
        self.scoringEngine = scoringEngine
    }

    @discardableResult
    public func save(
        _ request: SessionSaveRequest,
        to repository: any RangeSightRepository
    ) async throws -> SessionSaveResult {
        let scoringResult = try scoringEngine.score(
            correctionState: request.correctionState,
            targetDefinitionID: request.targetDefinition.id
        )
        let scoredShots = try scoringEngine.shotsForPersistence(
            correctionState: request.correctionState,
            targetDefinitionID: request.targetDefinition.id
        )

        var store = try await repository.loadStore()
        if let firearmProfile = request.firearmProfile {
            store.firearmProfiles.upsert(firearmProfile, matching: \.id)
        }
        store.targetDefinitions.upsert(request.targetDefinition, matching: \.id)
        store.rangeSessions.upsert(request.session, matching: \.id)
        store.rangeStrings.upsert(request.rangeString, matching: \.id)
        store.impactCorrectionHistory.removeAll { $0.stringID == request.rangeString.id }
        store.impactCorrectionHistory.append(contentsOf: request.correctionState.impacts.filter { $0.stringID == request.rangeString.id })
        store.shots.removeAll { $0.stringID == request.rangeString.id }
        store.shots.append(contentsOf: scoredShots)

        try await repository.replaceStore(store)

        return SessionSaveResult(
            sessionID: request.session.id,
            stringID: request.rangeString.id,
            acceptedShotCount: scoredShots.count,
            correctionHistoryCount: request.correctionState.impacts.filter { $0.stringID == request.rangeString.id }.count,
            scoringResult: scoringResult
        )
    }
}

private extension Array {
    mutating func upsert<ID: Equatable>(_ element: Element, matching keyPath: KeyPath<Element, ID>) {
        let id = element[keyPath: keyPath]

        if let index = firstIndex(where: { $0[keyPath: keyPath] == id }) {
            self[index] = element
        } else {
            append(element)
        }
    }
}
