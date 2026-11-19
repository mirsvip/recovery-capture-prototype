import Foundation
import SwiftData
import XCTest
@testable import RecoveryCore

final class RecoveryCoreTests: XCTestCase {
    private func payload(
        id: UUID = UUID(), habitID: UUID = UUID(), occurred: TimeInterval = 45,
        recorded: TimeInterval = 500, kind: CaptureKind = .completion,
        source: String = "test-watch"
    ) -> CapturePayload {
        CapturePayload(
            eventID: id, habitID: habitID,
            occurredAt: Date(timeIntervalSince1970: occurred),
            recordedAt: Date(timeIntervalSince1970: recorded),
            kind: kind, sourceDeviceID: source
        )
    }

    func testEventAndOutboxSurviveStoreReopening() async throws {
        let capture = payload()
        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("recovery-test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("watch.store")
            do {
                let store = CaptureStore(container: try Persistence.local(at: url))
                try store.recordOnWatch(capture)
            }
            do {
                let reopened = CaptureStore(container: try Persistence.local(at: url))
                XCTAssertEqual(try reopened.captures(), [capture])
                XCTAssertEqual(try reopened.pendingCaptures(), [capture])
                try reopened.acknowledge(capture.eventID)
            }
            let acknowledged = CaptureStore(container: try Persistence.local(at: url))
            XCTAssertTrue(try acknowledged.pendingCaptures().isEmpty)
            XCTAssertEqual(try acknowledged.captures(), [capture])
        }
    }

    func testLostAcknowledgementAndPhoneRestartDoNotDuplicateEvent() async throws {
        let capture = payload()
        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("recovery-test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("phone.store")
            do {
                let store = CaptureStore(container: try Persistence.local(at: url))
                XCTAssertTrue(try store.ingestOnPhone(capture))
                // Simulate the process exiting before its ACK reaches the Watch.
            }
            let reopened = CaptureStore(container: try Persistence.local(at: url))
            guard case .capture(let retried) = try WireCodec.decode(
                WireCodec.encode(.capture(capture))
            ) else { return XCTFail("Expected a capture envelope") }
            XCTAssertFalse(try reopened.ingestOnPhone(retried))
            XCTAssertEqual(try reopened.captures(), [capture])
        }
    }

    func testConflictingPayloadCannotOverwriteAnExistingUUID() async throws {
        let id = UUID()
        let habit = UUID()
        let original = payload(id: id, habitID: habit)
        let changed = payload(id: id, habitID: habit, occurred: 99)
        try await MainActor.run {
            let store = CaptureStore(container: try Persistence.local(inMemory: true))
            try store.ingestOnPhone(original)
            XCTAssertThrowsError(try store.ingestOnPhone(changed)) {
                XCTAssertEqual($0 as? CaptureError, .conflictingEventID)
            }
            XCTAssertEqual(try store.captures(), [original])
        }
    }

    func testRepeatedWatchCaptureAndUnrelatedAckDoNotLosePendingData() async throws {
        let capture = payload()
        try await MainActor.run {
            let store = CaptureStore(container: try Persistence.local(inMemory: true))
            try store.recordOnWatch(capture)
            try store.recordOnWatch(capture)
            try store.acknowledge(UUID())
            XCTAssertEqual(try store.captures(), [capture])
            XCTAssertEqual(try store.pendingCaptures(), [capture])
        }
    }

    func testInvalidCaptureIsRejectedBeforePersistence() async throws {
        let invalid = payload(source: "")
        try await MainActor.run {
            let store = CaptureStore(container: try Persistence.local(inMemory: true))
            XCTAssertThrowsError(try store.recordOnWatch(invalid))
            XCTAssertTrue(try store.captures().isEmpty)
            XCTAssertTrue(try store.pendingCaptures().isEmpty)
        }
    }

}
