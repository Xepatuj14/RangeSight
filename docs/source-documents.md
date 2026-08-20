# RangeSight Source Documents

These project documents remain the product and slice-order authority for RangeSight. The architecture has been superseded by the native iOS migration: RangeSight is a fully native Swift and SwiftUI application, not a React Native or Expo app.

| Document | Purpose |
| --- | --- |
| `01_RangeSight_Product_Requirements.docx` | Product scope, MVP user, functional and non-functional requirements, exclusions, acceptance metrics. |
| `02_RangeSight_System_Architecture.docx` | iOS-first architecture, JS/native boundary, camera pipeline, state machine, command/event contracts. |
| `03_RangeSight_Computer_Vision_Spec.docx` | Deterministic detector philosophy, ROI lock, per-frame processing, confidence bands, debug instrumentation. |
| `04_RangeSight_UX_Workflows.docx` | Screen inventory, range UX constraints, live monitor layout, correction flow, failure copy, visual direction. |
| `05_RangeSight_Data_Model_Analytics.docx` | Coordinate systems, entities, shot sources, geometry metrics, scoring rules, persistence and privacy defaults. |
| `06_RangeSight_Testing_Validation.docx` | Testing pyramid, validation matrix, release gates, edge cases, replay harness requirement. |
| `07_RangeSight_Codex_Build_Roadmap.docx` | Ordered implementation slices, global coding rules, definition of done, milestone A. |

## Active Slice

Slice 6: Native camera preview.

Deliverable: Swift/AVFoundation permission handling, camera preview lifecycle, and SwiftUI preview surface. Slice 7 has not started.
