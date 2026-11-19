import Foundation
import SwiftData

// Cloud-backed entities use defaults and scalar UUID references. No unique
// constraints or required relationships: CloudKit cannot enforce those.
@Model
public final class Habit {
    public var id: UUID = UUID()
    public var name: String = ""
    public var createdAt: Date = Date()

    public init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

@Model
public final class ScheduleVersion {
    public var id: UUID = UUID()
    public var habitID: UUID = UUID()
    public var effectiveFrom: Date = Date()
    public var timeZoneID: String = "UTC"
    // Calendar weekday values: Sunday = 1, Saturday = 7.
    public var weekdays: [Int] = [1, 2, 3, 4, 5, 6, 7]
    public var opensAtMinute: Int = 0
    public var closesAtMinute: Int = 1440
    public var isPaused: Bool = false

    public init(
        id: UUID = UUID(), habitID: UUID, effectiveFrom: Date,
        timeZoneID: String = "UTC", weekdays: [Int] = [1, 2, 3, 4, 5, 6, 7],
        opensAtMinute: Int = 0, closesAtMinute: Int = 1440,
        isPaused: Bool = false
    ) {
        self.id = id
        self.habitID = habitID
        self.effectiveFrom = effectiveFrom
        self.timeZoneID = timeZoneID
        self.weekdays = weekdays
        self.opensAtMinute = opensAtMinute
        self.closesAtMinute = closesAtMinute
        self.isPaused = isPaused
    }
}

@Model
public final class CaptureEvent {
    public var eventID: UUID = UUID()
    public var habitID: UUID = UUID()
    public var occurredAt: Date = Date()
    public var recordedAt: Date = Date()
    public var kindRaw: String = "completion"
    public var sourceDeviceID: String = ""
    public var reason: String?

    public init(payload: CapturePayload) {
        eventID = payload.eventID
        habitID = payload.habitID
        occurredAt = payload.occurredAt
        recordedAt = payload.recordedAt
        kindRaw = payload.kind.rawValue
        sourceDeviceID = payload.sourceDeviceID
        reason = payload.reason
    }

    public func payload() throws -> CapturePayload {
        guard let kind = CaptureKind(rawValue: kindRaw) else {
            throw CaptureError.invalidPayload
        }
        return CapturePayload(
            eventID: eventID, habitID: habitID, occurredAt: occurredAt,
            recordedAt: recordedAt, kind: kind,
            sourceDeviceID: sourceDeviceID, reason: reason
        )
    }
}

// This entity belongs ONLY to the local Watch store, never the CloudKit schema.
@Model
public final class OutboxEntry {
    public var eventID: UUID = UUID()
    public var payloadData: Data = Data()
    public var createdAt: Date = Date()

    public init(payload: CapturePayload) throws {
        eventID = payload.eventID
        payloadData = try JSONEncoder().encode(payload)
        createdAt = payload.recordedAt
    }
}
