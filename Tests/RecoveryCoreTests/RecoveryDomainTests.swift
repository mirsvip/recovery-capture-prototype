import Foundation
import XCTest
@testable import RecoveryCore

final class RecoveryDomainTests: XCTestCase {
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

    func testWireEnvelopeIsPropertyListSafeAndRoundTrips() throws {
        let message = WireMessage.capture(payload())
        let dictionary = try WireCodec.encode(message)
        let bytes = try PropertyListSerialization.data(
            fromPropertyList: dictionary, format: .binary, options: 0
        )
        let restored = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: bytes, options: [], format: nil)
                as? [String: Any]
        )
        XCTAssertEqual(try WireCodec.decode(restored), message)
        let ack = WireMessage.acknowledgement(UUID())
        XCTAssertEqual(try WireCodec.decode(WireCodec.encode(ack)), ack)
    }

    func testUnsupportedVersionAndOversizedPayloadAreRejected() throws {
        var dictionary = try WireCodec.encode(.capture(payload()))
        dictionary["recoveryProtocol"] = 999
        XCTAssertThrowsError(try WireCodec.decode(dictionary)) {
            XCTAssertEqual($0 as? CaptureError, .unsupportedProtocol)
        }
        dictionary["recoveryProtocol"] = WireCodec.protocolVersion
        dictionary["body"] = Data(repeating: 0, count: 32_769)
        XCTAssertThrowsError(try WireCodec.decode(dictionary)) {
            XCTAssertEqual($0 as? CaptureError, .invalidPayload)
        }
    }

    func testRecoveryGroupsMissesAndUsesOccurrenceRatherThanArrivalTime() {
        let habit = UUID()
        let completion = payload(habitID: habit, occurred: 45, recorded: 500)
        let windows = [0.0, 20, 40, 60].map {
            ExpectedWindow(
                habitID: habit, opensAt: Date(timeIntervalSince1970: $0),
                closesAt: Date(timeIntervalSince1970: $0 + 10)
            )
        }
        let summary = RecoveryCalculator.summarize(
            habitID: habit, windows: windows,
            captures: [
                completion, completion,
                payload(habitID: habit, occurred: 5, kind: .note),
                payload(habitID: habit, occurred: 100),
                payload(occurred: 75), // Another habit cannot close this gap.
            ], asOf: Date(timeIntervalSince1970: 80)
        )
        XCTAssertEqual(summary.episodes.count, 2)
        XCTAssertEqual(summary.episodes.first?.missedWindowCount, 2)
        XCTAssertEqual(summary.episodes.first?.duration, 35)
        XCTAssertEqual(summary.medianClosedDuration, 35)
        XCTAssertEqual(summary.openEpisodes.count, 1)
        XCTAssertEqual(summary.openEpisodes.first?.startedAt, Date(timeIntervalSince1970: 70))
    }

    func testPlannedPauseAndCompletionAtDeadlineDoNotOpenGaps() {
        let habit = UUID()
        let windows = [
            ExpectedWindow(habitID: habit, opensAt: .init(timeIntervalSince1970: 0),
                           closesAt: .init(timeIntervalSince1970: 10), isPaused: true),
            ExpectedWindow(habitID: habit, opensAt: .init(timeIntervalSince1970: 20),
                           closesAt: .init(timeIntervalSince1970: 30)),
        ]
        let summary = RecoveryCalculator.summarize(
            habitID: habit, windows: windows,
            captures: [payload(habitID: habit, occurred: 30)],
            asOf: Date(timeIntervalSince1970: 40)
        )
        XCTAssertTrue(summary.episodes.isEmpty)
        XCTAssertNil(summary.medianClosedDuration)
    }

    func testUnresolvedGapDoesNotBecomeAZeroLengthRecovery() {
        let habit = UUID()
        let summary = RecoveryCalculator.summarize(
            habitID: habit,
            windows: [ExpectedWindow(
                habitID: habit, opensAt: .init(timeIntervalSince1970: 0),
                closesAt: .init(timeIntervalSince1970: 10)
            )], captures: [], asOf: Date(timeIntervalSince1970: 100)
        )
        XCTAssertEqual(summary.openEpisodes.count, 1)
        XCTAssertNil(summary.medianClosedDuration)
    }
}
