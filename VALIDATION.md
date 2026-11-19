# Validation record

Recorded for the initial implementation on 2026-11-19.

## Passed locally

```sh
sh Scripts/check-domain.sh
```

The check compiles the repository's actual `WireProtocol.swift` and
`Recovery.swift`, together with `Validation/DomainCheck.swift`, and runs the
resulting executable. The three checks passed:

- Capture identity and timestamps survive binary property-list serialization.
- An unsupported protocol version is rejected.
- Consecutive missed windows form one recovery episode, occurrence time rather
  than delivery time controls duration, and an unresolved gap remains visible.

These checks exercise Foundation-based domain code. They do not exercise
SwiftData persistence, WatchConnectivity, CloudKit, or UI.

## Local toolchain limitation

Full-package `swift test` was attempted. The installed Command Line Tools SDK
can import SwiftData but does not supply its `SwiftDataMacros` implementation,
so `@Model` expansion fails. The Command Line Tools installation also lacks
XCTest. The disk-persistence and acknowledgement-replay XCTest cases are
present in the repository but have not passed locally.

## Passed in GitHub Actions

[Swift core run 44500219378](https://github.com/mirsvip/recovery-capture-prototype/actions/runs/44500219378)
completed successfully for code commit `45d2dbb18bee021bec3bfa1b92fe2310a113be9a`.
Both substantive steps succeeded on the Xcode-equipped macOS runner:

- `swift test`: compile the full macOS package and run the XCTest suite,
  including real SwiftData disk persistence and replay checks.
- `swift run recovery-demo`: run the two-store persistence and acknowledgement
  simulation successfully.

The follow-up documentation commit records this evidence without changing the
tested Swift source. These macOS results do not compile iOS/watchOS-only code.

## Remaining device validation

The iPhone/watchOS transport branch, example app views, complication routing,
paired-device delivery, iCloud convergence, and battery cost remain unverified.
The README describes the integration steps and next physical-device checks.
