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
| `RangeSight/Analytics` | Future local analytics and diagnostics boundary. |
| `RangeSight/Replay` | Replay/validation boundary for recorded footage. |

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

Slices 1 and 2 were reimplemented natively:

- Slice 1: SwiftUI app shell, native navigation model, Xcode project/scheme, Swift package/test baseline, CI workflow.
- Slice 2: Swift domain models, normalized target coordinates, schema-versioned serialization, unit tests.
- Slice 3: Native scoring/geometry engine for physical coordinate conversion, group metrics, scoring-zone interfaces, score evaluation, and deterministic tests.

Slice 4 has not been implemented.

## Package.swift Decision

`Package.swift` is retained as a supplementary development and CI surface for isolated `RangeSightCore` testing. It is not the production app build path and must not replace `RangeSight.xcodeproj` for app validation.
