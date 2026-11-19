import Foundation

public enum CaptureKind: String, Codable, Sendable {
    case completion
    case note
}

public enum CaptureError: Error, Equatable {
    case invalidPayload
    case unsupportedProtocol
    case conflictingEventID
    case wrongTransportRole
    case sessionNotActivated
}

public struct CapturePayload: Codable, Equatable, Sendable {
    public let eventID: UUID
    public let habitID: UUID
    public let occurredAt: Date
    public let recordedAt: Date
    public let kind: CaptureKind
    public let sourceDeviceID: String
    public let reason: String?

    public init(
        eventID: UUID = UUID(), habitID: UUID, occurredAt: Date = Date(),
        recordedAt: Date = Date(), kind: CaptureKind = .completion,
        sourceDeviceID: String, reason: String? = nil
    ) {
        self.eventID = eventID
        self.habitID = habitID
        self.occurredAt = occurredAt
        self.recordedAt = recordedAt
        self.kind = kind
        self.sourceDeviceID = sourceDeviceID
        self.reason = reason
    }

    public func validate() throws {
        guard occurredAt.timeIntervalSince1970.isFinite,
              recordedAt.timeIntervalSince1970.isFinite,
              !sourceDeviceID.isEmpty, sourceDeviceID.utf8.count <= 256,
              (reason?.utf8.count ?? 0) <= 8192 else {
            throw CaptureError.invalidPayload
        }
    }
}

public enum WireMessage: Codable, Equatable, Sendable {
    case capture(CapturePayload)
    case acknowledgement(UUID)
}

public enum WireCodec {
    public static let protocolVersion = 1

    // WCSession dictionaries must contain property-list values. JSON bytes are
    // carried as Data, rather than sending SwiftData model objects or UUIDs.
    public static func encode(_ message: WireMessage) throws -> [String: Any] {
        if case .capture(let payload) = message { try payload.validate() }
        return [
            "recoveryProtocol": protocolVersion,
            "body": try JSONEncoder().encode(message),
        ]
    }

    public static func decode(_ dictionary: [String: Any]) throws -> WireMessage {
        guard let version = dictionary["recoveryProtocol"] as? Int,
              version == protocolVersion else {
            throw CaptureError.unsupportedProtocol
        }
        guard let data = dictionary["body"] as? Data,
              data.count <= 32_768 else {
            throw CaptureError.invalidPayload
        }
        let message = try JSONDecoder().decode(WireMessage.self, from: data)
        if case .capture(let payload) = message { try payload.validate() }
        return message
    }
}
