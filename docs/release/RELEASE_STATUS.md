# RangeSight Release Status

Slice 19 status: internal release hardening implemented.

## Decision

READY FOR INTERNAL TESTFLIGHT ONLY

Reason: source-level release hardening is in place, but this Windows environment cannot run Xcode, iOS Simulator, TestFlight, physical-device, or indoor-range validation. A green CI build is not equivalent to range validation.

## Gates

| Gate | Status | Evidence |
| --- | --- | --- |
| CI | NOT TESTED | Must be confirmed by macOS GitHub Actions after Slice 19 changes. |
| Simulator | NOT TESTED | Requires macOS/Xcode. |
| Physical iPhone | NOT TESTED | Requires device smoke test. |
| Indoor range | NOT TESTED | Requires controlled labeled data. |
| Accuracy gate | INSUFFICIENT DATA | No real Slice 19 range validation dataset is present. |

## Accuracy Gate

PRD targets:

- Impact precision >= 95%
- Impact recall >= 90%
- Fewer than 1 false impact per 20-shot controlled session

Current status:

- Precision: INSUFFICIENT DATA
- Recall: INSUFFICIENT DATA
- False positives per 20-shot session: INSUFFICIENT DATA
- Gate result: INSUFFICIENT DATA

## Schema Versions

- Domain schema: 1
- Persistence schema: 2
- Validation report schema: 1

Supported persistence upgrades:

- Version 1 to version 2: supported with empty defaults for correction history, diagnostics, and session assets when absent.
- Future versions: rejected as unsupported.
- Malformed persisted records: rejected; data is not fabricated.

Supported validation report upgrades:

- Version 1: supported.
- Future versions: rejected as unsupported until an explicit migration is added.

## Privacy / Retention

- Target analysis is on device.
- Raw camera frames are not uploaded by default.
- Audio Assist is optional; microphone samples are processed transiently for impulse timing.
- No account or network connection is required for core workflows.
- Exports leave app-controlled storage only when the user explicitly shares or exports.

## Known Release Blockers

P0: none known from static audit.

P1: none known from static audit.

P2:

- Physical iPhone smoke test not executed.
- Indoor-range validation not executed.
- Accuracy gate has insufficient data.
- Native Release build not executed locally; requires macOS CI.

P3:

- App icon/signing/app-store metadata require release-owner review.
