# RangeSight Native iOS Architecture

RangeSight is now a fully native iOS application written in Swift and SwiftUI. React Native, Expo, JavaScript, and TypeScript are no longer production architecture.

## Xcode Project

The production app build path is:

- Project: `RangeSight.xcodeproj`
- Shared scheme: `RangeSight`
- Application target: `RangeSight`
- Core framework target: `RangeSightCore`
- Unit test target: `RangeSightTests`
- Deployment target: iOS 17.0

iOS 17.0 is the current foundation target because it supports the SwiftUI, AVFoundation, Vision, and concurrency direction RangeSight needs without requiring only the newest OS generation.

The product requirements and slice order remain valid, but implementation must use native Apple-platform boundaries:

| Area | Responsibility |
| --- | --- |
| `RangeSight/App` | SwiftUI app lifecycle and root presentation. |
| `RangeSight/Features` | SwiftUI feature views and presentation state. |
| `RangeSight/Domain` | Platform-independent RangeSight entities, identifiers, coordinates, and serialization. |
| `RangeSight/SessionEngine` | Explicit range-session state transitions. |
| `RangeSight/Camera` | AVFoundation capture authorization and future frame delivery. |
| `RangeSight/Vision` | Native Vision/Core Image pipeline boundaries. |
| `RangeSight/Audio` | Audio impulse candidate boundary. |
| `RangeSight/Scoring` | Future target geometry, group metrics, and scoring evaluation. |
| `RangeSight/Persistence` | Local-first storage boundary. |
| `RangeSight/Analytics` | Local session history analytics and detector/correction summaries. |
| `RangeSight/Replay` | Replay harness boundary for recorded/labeled footage. |
| `RangeSight/Performance` | ROI extraction, scheduling, thermal/power policy, and performance diagnostics. |
| `RangeSight/Validation` | Internal replay/range validation reporting and export models. |
| `RangeSight/Release` | Release-hardening severity, permission, and privacy copy boundaries. |

## Development Workflow

The developer may work from Windows, VS Code, and Codex, but native compilation is authoritative in macOS CI and later TestFlight/device validation:

Windows / VS Code / Codex -> GitHub -> macOS CI / Xcode build -> TestFlight -> physical iPhone testing.

Routine CI must not require signing secrets. TestFlight signing and upload are separate release concerns.

## CI Validation

GitHub Actions workflow: `.github/workflows/native-ios.yml`

The workflow validates the real iOS application project by running:

```bash
xcodebuild -resolvePackageDependencies -project RangeSight.xcodeproj -scheme RangeSight
xcodebuild build -project RangeSight.xcodeproj -scheme RangeSight -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project RangeSight.xcodeproj -scheme RangeSight -destination "$DESTINATION" CODE_SIGNING_ALLOWED=NO
swift test
```

The Xcode build/test commands are authoritative for native app readiness. `swift test` remains as a supplementary check for the reusable core package.

## Migration Notes

Slices 1 through 19 have been implemented under the native architecture:

- Slice 1: SwiftUI app shell, native navigation model, Xcode project/scheme, Swift package/test baseline, CI workflow.
- Slice 2: Swift domain models, normalized target coordinates, schema-versioned serialization, unit tests.
- Slice 3: Native scoring/geometry engine for physical coordinate conversion, group metrics, scoring-zone interfaces, score evaluation, and deterministic tests.
- Slice 4: Native SwiftUI session UX shell for Home, setup, camera setup, live monitor mock, review, summary/history, firearm profile, and settings screens using fake presentation data.
- Slice 5: Local-first persistence boundary with schema-versioned JSON storage and create/read/update flows for sessions, strings, shots, firearm profiles, and target definitions.
- Slice 6: Native AVFoundation camera permission handling, preview session lifecycle, and SwiftUI preview surface.
- Slice 7: Target lock and ROI metadata.
- Slice 8: Replay harness.
- Slice 9: Frame registration.
- Slice 10: Registered frame difference/change detection.
- Slice 10.5: Registration transform applied to pixel data.
- Slice 11: Temporal confirmation.
- Slice 12: Live impact events.
- Slice 13: Correction workflow.
- Slice 13.5: Persisted correction history and raw detector evidence.
- Slice 14: Optional audio assist.
- Slice 15: Supported target scoring.
- Slice 16: Session history analytics.
- Slice 17: Performance hardening.
- Slice 18: Range validation tooling.
- Slice 19: Release hardening.

Current schema versions:

- Domain schema: 1
- Persistence schema: 2
- Validation report schema: 1

Release status is tracked in `docs/release/RELEASE_STATUS.md`. TestFlight readiness tasks are tracked in `docs/release/TESTFLIGHT_CHECKLIST.md`. A green CI build is not equivalent to physical range validation.

## Package.swift Decision

`Package.swift` is retained as a supplementary development and CI surface for isolated `RangeSightCore` testing. It is not the production app build path and must not replace `RangeSight.xcodeproj` for app validation.
