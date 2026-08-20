import Foundation

public struct SerializedDomainRecord<Payload: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let kind: String
    public let payload: Payload
}

public enum DomainSerializationError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case unexpectedKind(expected: String, actual: String)
}

public enum DomainSerializer {
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func record<Payload: Codable & Equatable & Sendable>(
        kind: String,
        payload: Payload
    ) -> SerializedDomainRecord<Payload> {
        SerializedDomainRecord(
            schemaVersion: DomainSchema.currentVersion,
            kind: kind,
            payload: payload
        )
    }

    public static func payload<Payload: Codable & Equatable & Sendable>(
        from record: SerializedDomainRecord<Payload>,
        expectedKind: String
    ) throws -> Payload {
        guard record.schemaVersion == DomainSchema.currentVersion else {
            throw DomainSerializationError.unsupportedSchemaVersion(record.schemaVersion)
        }
        guard record.kind == expectedKind else {
            throw DomainSerializationError.unexpectedKind(expected: expectedKind, actual: record.kind)
        }
        return record.payload
    }
}
