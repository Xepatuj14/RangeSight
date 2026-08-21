import Foundation

public actor LocalRangeSightRepository: RangeSightRepository {
    private let storeURL: URL
    private let fileManager: FileManager

    public init(storeURL: URL, fileManager: FileManager = .default) {
        self.storeURL = storeURL
        self.fileManager = fileManager
    }

    public func loadStore() async throws -> PersistedRangeSightStore {
        guard fileManager.fileExists(atPath: storeURL.path) else {
            return PersistedRangeSightStore()
        }

        let data = try Data(contentsOf: storeURL)
        let store = try Self.makeDecoder().decode(PersistedRangeSightStore.self, from: data)
        return try migratedStore(from: store)
    }

    public func replaceStore(_ store: PersistedRangeSightStore) async throws {
        try write(migratedStore(from: store))
    }

    public func upsertFirearmProfile(_ profile: FirearmProfile) async throws {
        try await mutateStore { store in
            store.firearmProfiles.upsert(profile, matching: \.id)
        }
    }

    public func upsertTargetDefinition(_ target: TargetDefinition) async throws {
        try await mutateStore { store in
            store.targetDefinitions.upsert(target, matching: \.id)
        }
    }

    public func upsertRangeSession(_ session: RangeSession) async throws {
        try await mutateStore { store in
            store.rangeSessions.upsert(session, matching: \.id)
        }
    }

    public func rangeSession(id: RangeSessionID) async throws -> RangeSession? {
        let store = try await loadStore()
        return store.rangeSessions.first { $0.id == id }
    }

    public func rangeSessions() async throws -> [RangeSession] {
        let store = try await loadStore()
        return store.rangeSessions.sorted { $0.startedAt > $1.startedAt }
    }

    public func upsertRangeString(_ rangeString: RangeString) async throws {
        try await mutateStore { store in
            guard store.rangeSessions.contains(where: { $0.id == rangeString.sessionID }) else {
                throw PersistenceError.missingRangeSession(rangeString.sessionID)
            }
            store.rangeStrings.upsert(rangeString, matching: \.id)
        }
    }

    public func rangeStrings(sessionID: RangeSessionID) async throws -> [RangeString] {
        let store = try await loadStore()
        return store.rangeStrings
            .filter { $0.sessionID == sessionID }
            .sorted { $0.index < $1.index }
    }

    public func upsertShot(_ shot: Shot) async throws {
        try await mutateStore { store in
            guard store.rangeStrings.contains(where: { $0.id == shot.stringID }) else {
                throw PersistenceError.missingRangeString(shot.stringID)
            }
            store.shots.upsert(shot, matching: \.id)
        }
    }

    public func shots(stringID: RangeStringID) async throws -> [Shot] {
        let store = try await loadStore()
        return store.shots
            .filter { $0.stringID == stringID }
            .sorted { $0.ordinal < $1.ordinal }
    }

    public func replaceImpactCorrectionState(_ state: ImpactCorrectionState, stringID: RangeStringID) async throws {
        let shots = try state.shotsForPersistence().filter { $0.stringID == stringID }
        try await mutateStore { store in
            guard store.rangeStrings.contains(where: { $0.id == stringID }) else {
                throw PersistenceError.missingRangeString(stringID)
            }

            store.impactCorrectionHistory.removeAll { $0.stringID == stringID }
            store.impactCorrectionHistory.append(contentsOf: state.impacts.filter { $0.stringID == stringID })
            store.shots.removeAll { $0.stringID == stringID }
            store.shots.append(contentsOf: shots)
        }
    }

    public func replaceImpactCorrectionHistory(_ impacts: [AcceptedImpact], stringID: RangeStringID) async throws {
        try await mutateStore { store in
            guard store.rangeStrings.contains(where: { $0.id == stringID }) else {
                throw PersistenceError.missingRangeString(stringID)
            }

            store.impactCorrectionHistory.removeAll { $0.stringID == stringID }
            store.impactCorrectionHistory.append(contentsOf: impacts.filter { $0.stringID == stringID })
        }
    }

    public func impactCorrectionHistory(stringID: RangeStringID) async throws -> [AcceptedImpact] {
        let store = try await loadStore()
        return store.impactCorrectionHistory
            .filter { $0.stringID == stringID }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.rawValue < rhs.id.rawValue
                }

                return lhs.createdAt < rhs.createdAt
            }
    }

    public func impactCorrectionState(stringID: RangeStringID) async throws -> ImpactCorrectionState {
        ImpactCorrectionState(impacts: try await impactCorrectionHistory(stringID: stringID))
    }

    private func mutateStore(_ mutation: (inout PersistedRangeSightStore) throws -> Void) async throws {
        var store = try await loadStore()
        try mutation(&store)
        try write(store)
    }

    private func write(_ store: PersistedRangeSightStore) throws {
        let store = try migratedStore(from: store)
        let directory = storeURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.makeEncoder().encode(store)
        try data.write(to: storeURL, options: [.atomic])
    }

    private func migratedStore(from store: PersistedRangeSightStore) throws -> PersistedRangeSightStore {
        guard (1...PersistenceSchema.currentVersion).contains(store.schemaVersion) else {
            throw PersistenceError.unsupportedSchemaVersion(store.schemaVersion)
        }

        guard store.schemaVersion != PersistenceSchema.currentVersion else {
            return store
        }

        return PersistedRangeSightStore(
            firearmProfiles: store.firearmProfiles,
            targetDefinitions: store.targetDefinitions,
            rangeSessions: store.rangeSessions,
            rangeStrings: store.rangeStrings,
            shots: store.shots,
            impactCorrectionHistory: store.impactCorrectionHistory,
            detectionDiagnostics: store.detectionDiagnostics,
            sessionAssets: store.sessionAssets
        )
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
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
