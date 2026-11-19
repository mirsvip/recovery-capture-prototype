import Foundation
import SwiftData

public enum Persistence {
    public static func local(
        at url: URL? = nil, inMemory: Bool = false
    ) throws -> ModelContainer {
        let schema = Schema([
            Habit.self, ScheduleVersion.self, CaptureEvent.self, OutboxEntry.self,
        ])
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(
                schema: schema, url: url, cloudKitDatabase: .none
            )
        } else {
            configuration = ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: inMemory,
                cloudKitDatabase: .none
            )
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    // Requires an app target with the real container's iCloud entitlement and
    // remote-notification capability. This factory does not provision either.
    public static func cloud(containerIdentifier: String) throws -> ModelContainer {
        let schema = Schema([Habit.self, ScheduleVersion.self, CaptureEvent.self])
        let configuration = ModelConfiguration(
            schema: schema, cloudKitDatabase: .private(containerIdentifier)
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

// One writer owns event ingestion per device. A fetch-then-insert performed by
// several unrelated contexts would not provide idempotency.
@MainActor
public final class CaptureStore {
    private let context: ModelContext

    public init(container: ModelContainer) {
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    public func recordOnWatch(_ payload: CapturePayload) throws {
        try payload.validate()
        if let existing = try event(withID: payload.eventID) {
            guard try existing.payload() == payload else {
                throw CaptureError.conflictingEventID
            }
            return
        }
        let outbox = try OutboxEntry(payload: payload)
        context.insert(CaptureEvent(payload: payload))
        context.insert(outbox)
        // Event and outbox are committed in the same local transaction.
        try saveOrRollback()
    }

    @discardableResult
    public func ingestOnPhone(_ payload: CapturePayload) throws -> Bool {
        try payload.validate()
        if let existing = try event(withID: payload.eventID) {
            guard try existing.payload() == payload else {
                throw CaptureError.conflictingEventID
            }
            return false
        }
        context.insert(CaptureEvent(payload: payload))
        try saveOrRollback()
        return true
    }

    public func pendingCaptures() throws -> [CapturePayload] {
        let descriptor = FetchDescriptor<OutboxEntry>(
            sortBy: [SortDescriptor(\OutboxEntry.createdAt)]
        )
        return try context.fetch(descriptor).map {
            let payload = try JSONDecoder().decode(CapturePayload.self, from: $0.payloadData)
            try payload.validate()
            guard payload.eventID == $0.eventID else {
                throw CaptureError.invalidPayload
            }
            return payload
        }
    }

    public func acknowledge(_ eventID: UUID) throws {
        let descriptor = FetchDescriptor<OutboxEntry>(
            predicate: #Predicate { $0.eventID == eventID }
        )
        for entry in try context.fetch(descriptor) { context.delete(entry) }
        try saveOrRollback()
    }

    public func captures() throws -> [CapturePayload] {
        let descriptor = FetchDescriptor<CaptureEvent>(
            sortBy: [SortDescriptor(\CaptureEvent.occurredAt)]
        )
        return try context.fetch(descriptor).map { try $0.payload() }
    }

    private func event(withID id: UUID) throws -> CaptureEvent? {
        var descriptor = FetchDescriptor<CaptureEvent>(
            predicate: #Predicate { $0.eventID == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func saveOrRollback() throws {
        do { try context.save() }
        catch {
            context.rollback()
            throw error
        }
    }
}
