import Foundation

@main
struct DomainCheck {
    enum Failure: Error { case checkFailed(String) }

    static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure.checkFailed(message) }
    }

    static func main() throws {
        let habitID = UUID()
        let capture = CapturePayload(
            habitID: habitID, occurredAt: .init(timeIntervalSince1970: 45),
            recordedAt: .init(timeIntervalSince1970: 500), sourceDeviceID: "domain-check"
        )
        let envelope = try WireCodec.encode(.capture(capture))
        let bytes = try PropertyListSerialization.data(
            fromPropertyList: envelope, format: .binary, options: 0
        )
        guard let restored = try PropertyListSerialization.propertyList(
            from: bytes, options: [], format: nil
        ) as? [String: Any] else { throw Failure.checkFailed("property-list type") }
        try require(try WireCodec.decode(restored) == .capture(capture), "payload round trip")
        print("PASS: capture survives property-list serialization without changing identity or time.")

        var unknown = envelope
        unknown["recoveryProtocol"] = 999
        do {
            _ = try WireCodec.decode(unknown)
            throw Failure.checkFailed("unknown protocol accepted")
        } catch CaptureError.unsupportedProtocol {
            print("PASS: unsupported protocol version is rejected.")
        }

        let windows = [0.0, 20, 40, 60].map {
            ExpectedWindow(
                habitID: habitID, opensAt: .init(timeIntervalSince1970: $0),
                closesAt: .init(timeIntervalSince1970: $0 + 10)
            )
        }
        let note = CapturePayload(
            habitID: habitID, occurredAt: .init(timeIntervalSince1970: 5),
            kind: .note, sourceDeviceID: "domain-check"
        )
        let summary = RecoveryCalculator.summarize(
            habitID: habitID, windows: windows, captures: [capture, capture, note],
            asOf: .init(timeIntervalSince1970: 80)
        )
        try require(summary.episodes.count == 2, "episode count")
        try require(summary.episodes.first?.missedWindowCount == 2, "consecutive gaps")
        try require(summary.medianClosedDuration == 35, "occurrence-time recovery duration")
        try require(summary.openEpisodes.count == 1, "unresolved gap remains visible")
        print("PASS: recovery groups misses, uses event time, and retains unresolved gaps.")
        print("3 domain checks passed. SwiftData persistence, WatchConnectivity and CloudKit were not exercised.")
    }
}
