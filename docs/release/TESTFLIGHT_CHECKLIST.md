# RangeSight TestFlight Checklist

Status values:

- `[ ]` Not verified for this release candidate
- `[x]` Verified for this release candidate
- `[n/a]` Not applicable

## Build

- [ ] Native Release build succeeds on macOS CI
- [ ] Unit tests are green
- [ ] No compiler errors
- [ ] No known P0/P1 release blockers

## Permissions

- [ ] Camera request verified from camera setup
- [ ] Camera denied state verified with Settings guidance
- [ ] Microphone optional request verified when Audio Assist is enabled
- [ ] Microphone denied state verified with visual fallback

## Camera

- [ ] Preview works
- [ ] Target lock works
- [ ] Orientation verified
- [ ] ROI path verified
- [ ] Background/interruption behavior verified

## Computer Vision

- [ ] Registration recovery verified
- [ ] No-change case verified
- [ ] Global-lighting rejection verified
- [ ] Candidate persistence verified
- [ ] Known-impact suppression verified

## Adjacent-Lane Isolation

- [ ] Two targets visible at same distance
- [ ] Lock user's target A
- [ ] Change target B only -> no impact
- [ ] Loud neighboring shot + no A change -> no impact
- [ ] Loud neighboring shot + B change -> no impact
- [ ] A change -> impact detected
- [ ] A + B change -> only A detected
- [ ] Small camera bump -> tracking survives
- [ ] Large camera bump toward B -> target lost/re-lock
- [ ] Re-lock same target -> old holes not rediscovered

## Session

- [ ] Start/end verified
- [ ] Shot ordering verified
- [ ] Correction workflow verified
- [ ] Scoring verified
- [ ] Save/reload verified

## Audio

- [ ] Audio Assist off verified
- [ ] Impulse support verified
- [ ] Neighbor-lane impulse produces no shot by itself

## History

- [ ] History reload verified
- [ ] Analytics filters verified
- [ ] Older-session compatibility verified

## Privacy

- [ ] On-device privacy copy verified
- [ ] No hidden uploads verified
- [ ] Usage descriptions verified

## Performance

- [ ] 5-10 minute sustained session verified
- [ ] No runaway memory verified
- [ ] Preview responsiveness verified
- [ ] Thermal behavior reviewed

## Validation

- [ ] Controlled range run completed
- [ ] Validation report exported
- [ ] Known false positives documented

## Physical Device Smoke Test

1. Fresh install.
2. Open app.
3. Start New Session.
4. Verify camera permission prompt appears only from camera setup.
5. Select supported target and distance.
6. Lock target.
7. Start string.
8. Verify live preview remains responsive.
9. End string.
10. Add, move, and delete one impact.
11. Verify score and group result.
12. Save.
13. Open History.
14. Relaunch.
15. Confirm session survives relaunch.
16. Enable Audio Assist.
17. Verify microphone permission prompt.
18. Confirm visual-only operation still works with Audio Assist disabled or denied.
19. Export validation report from an internal build if exposed.

This checklist is not evidence of execution. Mark items only after the release candidate is tested.
