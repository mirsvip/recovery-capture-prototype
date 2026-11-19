# Recovery Capture Prototype

An initial Swift implementation of a habit app that measures return after an
unlogged scheduled window, rather than maintaining a streak.

**Status: source prototype.** The core uses real SwiftData persistence and has
automated tests. The repository includes WatchConnectivity integration source
and Watch UI/complication examples. It does not yet contain a signed Xcode app,
a TestFlight build, or a paired-device demonstration. There are no user-retention
or battery-life measurements.

See [VALIDATION.md](VALIDATION.md) for the actual checks performed and their limits.

## Run locally

Requires macOS 14 or later and full Xcode with its SwiftData macro implementation.
There are no third-party package dependencies.

```sh
swift test
swift run recovery-demo
```

With only Command Line Tools, run `sh Scripts/check-domain.sh` instead. That
command compiles the actual wire-protocol and recovery-calculation sources with
a small executable validation harness. It does not compile or test SwiftData
persistence or Watch transport. Importing SwiftData alone is not enough to
expand `@Model` macros; full Xcode also supplies the XCTest framework.

The executable creates two temporary on-disk stores and simulates delivery:

1. Save a capture and its outbox item in one Watch-local transaction.
2. Deliver the same event twice to the simulated phone; keep one event.
3. Acknowledge persistence and remove only the outbox item, retaining history.

This is a local simulation, not a real WatchConnectivity or CloudKit transfer.

## Data model

| SwiftData model | Purpose |
| --- | --- |
| `Habit` | UUID, name, creation date. |
| `ScheduleVersion` | Habit UUID, effective date, time zone, weekdays, completion window, pause flag. Append new versions when changing a schedule. |
| `CaptureEvent` | Event UUID, habit UUID, occurrence time, recording time, kind, source installation, optional user-entered reason. |
| `OutboxEntry` | Local-only encoded event awaiting a phone persistence acknowledgement. |

Cloud-backed models have property defaults or optional values and use scalar
UUID references. They avoid unique constraints and required relationships.
`Persistence.cloud(containerIdentifier:)` excludes `OutboxEntry` entirely.
`Persistence.local(...)` explicitly disables CloudKit, including on Watch.

`CaptureStore` serializes ingestion through one main-actor-owned context with
autosave disabled. It validates event identity before deduplicating and saves
the event and outbox together. Reusing an event UUID with different content is
an error. The UUID is generated once at capture, never anew for a retry.

This is application-level replay handling, not a global uniqueness guarantee
from CloudKit. App targets must route ingestion through the same store service.

## Transport

```text
Watch: SwiftData event + durable outbox
    -> WCSession.transferUserInfo (queued, independent of isReachable)
    -> iPhone: validate, deduplicate, save, then acknowledge
    -> SwiftData / private CloudKit
    -> Mac: SwiftData / recovery review
```

`sendMessage` is an optional reachable fast path and uses the same UUID as the
queued payload. Successful WatchConnectivity transfer completion does not
clear the outbox: only the phone's persistence ACK does. A lost ACK is recovered
by replaying the same event; the phone acknowledges a matching duplicate too.
Pending records are retried on activation, reachability changes, or an explicit
foreground flush. There is no polling timer or tight failure-retry loop.

The payload is a versioned property-list dictionary containing JSON `Data`.
The receiver decodes on the delegate callback thread, then performs persistence
on the main actor. Unknown protocol versions and oversized payloads are rejected.

iPhone and Mac app targets must use the same private CloudKit container and
Apple account. Cloud synchronization is asynchronous; a successful local save
does not mean the event has reached the Mac. The factory in this package does
not create entitlements, provision a container, or deploy a CloudKit schema.

## Recovery metric

`RecoveryCalculator` derives episodes from explicit scheduled windows and
completion events:

- Start at the first closed window without a logged completion.
- Group subsequent missed windows into that episode until the next completion.
- Calculate time to return using the event's occurrence time, not its sync time.
- Paused windows do not open or increment episodes. Notes do not count as completions.
- Show median closed-episode duration alongside the number and age of open gaps.
- A completion exactly at the deadline still satisfies its window.

An absent log is **unlogged activity**, not evidence that the person failed to
perform the habit. `RecoveryEpisode` is a local derived value, not a synchronized
counter. Late events can change the projection when it is recomputed.
Duration is elapsed wall time; subtracting pauses inside an already-open gap
is not implemented in this version.

The prototype accepts explicit `ExpectedWindow` values. Expanding
`ScheduleVersion` history into calendar windows, including travel, DST changes,
schedule editing and pause boundaries, remains app-integration work. Do not use
the model's weekday fields as if that scheduler already existed.

## Watch capture and battery design

`Examples/CaptureComplication.swift` provides a static WidgetKit launcher with
`widgetURL` and a `.never` reload policy. It opens the dedicated capture screen;
a confirmation tap saves locally. `Examples/WatchCaptureView.swift` plays the
success haptic only after that save and labels the result “Saved on Watch.”

The complication performs no network requests. Transport runs after user capture
or lifecycle events and delegates queued delivery to the operating system.
Battery cost still needs physical-device profiling; no battery percentage or
latency claim has been measured.

## Integrating app targets

1. Create iPhone, companion Watch, Watch Widget Extension, and Mac targets in Xcode.
2. Add this package locally. Link `RecoveryCore` everywhere and
   `RecoveryWatchTransport` only in iPhone and Watch app targets.
3. Retain one `CaptureStore` and one `WatchConnectivityBridge` per app process.
   Use `.watch` with a local store; use `.phone` with the cloud-backed store.
4. Configure the actual iCloud container and remote-notification capabilities
   on iPhone/Mac. Initialize and deploy the development schema deliberately.
5. Add the example views to their respective targets and register the
   `recoverycapture` URL scheme in the Watch app. Supply a real selected habit
   UUID and persist the source installation identifier.
6. Connect foreground activation to `flushOutbox()`, surface transport errors,
   and implement habit/configuration delivery back to Watch. The latter is not
   implemented in this commit; `updateApplicationContext` is the intended path
   for a replaceable latest-configuration snapshot, not capture events.

## Validation scope

The local tests cover disk-store reopening, lost acknowledgements and replay,
conflicting UUID rejection, property-list serialization, invalid messages, and
recovery calculations with unresolved gaps, pauses, duplicate events, and
delayed arrival.

The development machine has Command Line Tools without full Xcode or the
SwiftData model macro implementation. Full-package compilation and persistence
tests cannot run locally with that setup. The iOS/watchOS conditional transport
branch and example UI files also need their platform SDKs. The CI workflow is
configured to run the full macOS core tests and simulation on Xcode-equipped
runners; it does not validate those conditional branches. A configured workflow
is not evidence of a successful run: consult the actual Actions result.

The next device acceptance test is: capture offline, relaunch without loss,
reconnect, verify exactly one event on iPhone, observe eventual arrival on Mac,
and repeat delivery without duplicating history. Also test receiver-save
failure, ACK loss, pairing lifecycle and an energy-profile baseline. Apple
requires paired physical devices to validate `transferUserInfo` delivery.

## Apple references

- [SwiftData and iCloud schema requirements](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)
- [Queued WatchConnectivity delivery](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferuserinfo(_:))
- [Widget URL routing](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension)
- [Widget refresh budgets](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)
