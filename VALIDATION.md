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

## Automated and device validation

`.github/workflows/swift.yml` configures full core tests and the persistence
simulation on a macOS runner with Xcode. Its actual Actions result must be
checked separately; adding the workflow does not establish that it passed.

The iPhone/watchOS transport branch, example app views, complication routing,
paired-device delivery, iCloud convergence, and battery cost remain unverified.
The README describes the integration steps and next physical-device checks.
