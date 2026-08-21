# RangeSight Flow Soft-Lock Audit

Slice 19.5 invariant:

Every non-terminal user-facing state must provide either an automatic bounded transition or a user-controlled escape action. No state may require an external event with no timeout and no escape.

## End-to-End Production Flow

1. App launch.
2. Home.
3. New Session.
4. Session Setup.
5. Camera Setup.
6. Camera permission check/request.
7. Camera preview startup.
8. Target framing and quality panel.
9. Target lock button becomes available when quality passes.
10. Live Monitor.
11. Optional Audio Assist status.
12. Impact event display/correction controls.
13. End String.
14. String Review.
15. Add, move, delete, or confirm impacts.
16. Scoring/group summary from accepted final coordinates.
17. Save String to Session Summary.
18. History.
19. Session detail.

Settings and History remain reachable from the tab strip. Validation tooling remains internal model/report code and is not exposed as normal release UI.

## State Transition Matrix

| From | Event | To | Async Dependency | Max Expected Wait | Failure State | Recovery Action |
| --- | --- | --- | --- | --- | --- | --- |
| Home | New Session | Session Setup | none | immediate | n/a | Home/History/Settings |
| Session Setup | Continue to Camera | Camera Setup | none | immediate | n/a | Home tab |
| Camera Setup | View appears | Camera permission | system permission if not determined | system controlled | Camera unavailable/permission required | Back/Home, Settings guidance |
| Camera permission | authorized | Camera starting | AVFoundation configuration | 8 seconds | Camera startup timed out | Retry Camera, Back/Home |
| Camera permission | denied/restricted | Camera permission required | none | immediate | Camera unavailable | Settings guidance, Back/Home |
| Camera starting | configured | Camera preview running | AVFoundation callback | 8 seconds | Camera startup timed out | Retry Camera, Back/Home |
| Target framing | quality passes | Target lock ready | synchronous target assessment | immediate | Lock unavailable | Reposition/change lock source/back |
| Target lock ready | Lock Target | Live Monitor | current implementation navigation | immediate | n/a | Pause/End String |
| Live Monitor | End String | String Review | none | immediate | n/a | Review controls |
| Live Monitor | Pause | Camera Setup | camera stop async, non-blocking | immediate UI transition | n/a | Restart/re-lock |
| Live Monitor | degraded analysis | Live Monitor degraded | frame processing diagnostics | no active-string timeout | Degraded | End String, Pause/re-lock |
| String Review | Add/Move | Edit mode | none | immediate | n/a | Cancel Add/Cancel Move/Clear |
| String Review | Confirm candidate | Review updated | none | immediate | n/a | Clear/Delete/Save |
| String Review | Save String | Session Summary | current mock flow immediate | immediate | n/a | History/Home |
| History | load | History list/empty/error | local repository | local file operation | Unable to load history | Home/Settings, reopen History |
| Settings | toggle Audio Assist | Settings updated | none until audio source starts | immediate | Audio unavailable | Visual workflow continues |

## Terminal-Wait States

| State | Exit Guarantee |
| --- | --- |
| Camera permission | System permission callback or already-known authorization state. User can leave via navigation. |
| Camera starting | 8-second startup timeout plus Retry Camera and Back/Home. |
| Target lock blocked | No spinner; user can reposition, change source, or leave. |
| Baseline acquisition | Policy documented as 8 seconds for the production baseline path when wired; current UI has no separate baseline wait state. |
| Monitoring degraded | No inactivity timeout; End String remains available. |
| Saving | Current UI save is immediate. Release save policy requires success/failure/retry for real persistence save flow. |
| History loading | Repository success/failure updates state; navigation remains available. |

## Timeout Policies

| Operation | Duration | Reason | Recovery |
| --- | --- | --- | --- |
| Camera startup | 8 seconds | Hardware/session callbacks must not leave preview in Starting forever. | Camera startup timed out, Retry Camera, Back/Home. |
| Target lock attempt | 5 seconds | A single future lock attempt should be bounded. | Adjust framing and retry or back out. |
| Baseline acquisition | 8 seconds | Start String must not wait indefinitely for valid baseline frames. | Re-lock, retry, end, or cancel. |
| Persistence save | none | Local atomic file write throws synchronously behind async boundary. | Exit saving state, show retry, preserve in-memory session. |
| Validation export | none | Deterministic encoding/writing with throwing failure paths. | Report failure and allow retry/cancel. |

Active strings have no inactivity timeout. A shooter may wait indefinitely between shots until they choose End String or the app enters an explicit recoverable failure/degraded state.

## Disabled Controls

| Control | Disabled Condition | Escape |
| --- | --- | --- |
| Lock Target | Target quality cannot lock. | Reposition, switch source, or leave camera setup. |
| Confirm | No medium candidate selected. | Select candidate or continue review. |
| Move/Delete | No shot selected. | Select shot, add impact, or save/end review. |

No critical escape action is disabled by analysis state in the current UI. End String is available in Live Monitor independent of CV/audio state.

## Physical TestFlight Risks

- Actual AVFoundation first-frame delivery is not testable on Windows.
- Background/foreground camera interruption needs physical iPhone verification.
- Baseline acquisition is policy-scaffolded; future production Start String implementation must apply the documented timeout.
- Real persistence-backed Save UI still needs the explicit saving/failure/retry state when mock flow is replaced.
