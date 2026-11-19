import Foundation
import RecoveryCore

@main
struct RecoveryDemo {
    @MainActor
    static func main() throws {
        print("Local persistence simulation; no WatchConnectivity or CloudKit network calls.")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("recovery-capture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let watch = CaptureStore(container: try Persistence.local(
            at: directory.appendingPathComponent("watch.store")
        ))
        let phone = CaptureStore(container: try Persistence.local(
            at: directory.appendingPathComponent("phone.store")
        ))
        let habitID = UUID()
        let payload = CapturePayload(habitID: habitID, sourceDeviceID: "demo-watch")
        try watch.recordOnWatch(payload)
        print("1. Capture saved locally. Pending outbox: \(try watch.pendingCaptures().count)")

        let wire = try WireCodec.encode(.capture(payload))
        guard case .capture(let delivered) = try WireCodec.decode(wire) else {
            throw CaptureError.invalidPayload
        }
        try phone.ingestOnPhone(delivered)
        try phone.ingestOnPhone(delivered)
        print("2. Delivered twice. Phone event count: \(try phone.captures().count)")
        let ack = try WireCodec.encode(.acknowledgement(payload.eventID))
        if case .acknowledgement(let eventID) = try WireCodec.decode(ack) {
            try watch.acknowledge(eventID)
        }
        print("3. Persistence ACK received. Pending outbox: \(try watch.pendingCaptures().count)")
        print("Watch retains its capture history: \(try watch.captures().count) event.")
    }
}
