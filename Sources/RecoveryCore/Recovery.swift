import Foundation

public struct ExpectedWindow: Equatable, Sendable {
    public let habitID: UUID
    public let opensAt: Date
    public let closesAt: Date
    public let isPaused: Bool

    public init(habitID: UUID, opensAt: Date, closesAt: Date, isPaused: Bool = false) {
        self.habitID = habitID
        self.opensAt = opensAt
        self.closesAt = closesAt
        self.isPaused = isPaused
    }
}

// A derived projection, not a synchronized SwiftData entity. Device arrival
// order and transport retries must not change the recovery calculation.
public struct RecoveryEpisode: Equatable, Sendable {
    public let habitID: UUID
    public let startedAt: Date
    public let resumedAt: Date?
    public var missedWindowCount: Int

    public var duration: TimeInterval? {
        resumedAt.map { $0.timeIntervalSince(startedAt) }
    }
}

public struct RecoverySummary: Equatable, Sendable {
    public let episodes: [RecoveryEpisode]

    public var openEpisodes: [RecoveryEpisode] {
        episodes.filter { $0.resumedAt == nil }
    }

    // Only closed episodes have a duration. Always show openEpisodes beside
    // this number: excluding unresolved gaps can otherwise hide deterioration.
    public var medianClosedDuration: TimeInterval? {
        let durations = episodes.compactMap(\.duration).sorted()
        guard !durations.isEmpty else { return nil }
        let middle = durations.count / 2
        return durations.count.isMultiple(of: 2)
            ? (durations[middle - 1] + durations[middle]) / 2
            : durations[middle]
    }
}

public enum RecoveryCalculator {
    // Windows are supplied explicitly in this prototype. A production schedule
    // expander must apply ScheduleVersion history, calendar/DST rules and pauses.
    // Completion at the closing instant still satisfies the window.
    public static func summarize(
        habitID: UUID, windows: [ExpectedWindow], captures: [CapturePayload],
        asOf: Date
    ) -> RecoverySummary {
        var seen = Set<UUID>()
        let completions = captures.filter {
            $0.habitID == habitID && $0.kind == .completion &&
            $0.occurredAt <= asOf && seen.insert($0.eventID).inserted
        }.sorted { $0.occurredAt < $1.occurredAt }
        let dueWindows = windows.filter {
            $0.habitID == habitID && !$0.isPaused &&
            $0.opensAt < $0.closesAt && $0.closesAt <= asOf
        }.sorted { $0.closesAt < $1.closesAt }

        var episodes: [RecoveryEpisode] = []
        for window in dueWindows {
            let logged = completions.contains {
                $0.occurredAt >= window.opensAt && $0.occurredAt <= window.closesAt
            }
            guard !logged else { continue }
            if let last = episodes.last,
               last.resumedAt == nil || window.closesAt <= last.resumedAt! {
                episodes[episodes.count - 1].missedWindowCount += 1
                continue
            }
            let next = completions.first { $0.occurredAt > window.closesAt }
            episodes.append(RecoveryEpisode(
                habitID: habitID, startedAt: window.closesAt,
                resumedAt: next?.occurredAt, missedWindowCount: 1
            ))
        }
        return RecoverySummary(episodes: episodes)
    }
}
