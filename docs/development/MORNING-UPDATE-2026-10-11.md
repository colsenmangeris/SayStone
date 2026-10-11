# SayStone morning update October 11 2026

SayStone's Mac utilities are implemented and received further isolation,
persistence and cancellation fixes overnight. A signed Development app is ready
for review. Native Computer Use successfully opened the synthetic workspace and
verified search/trim, but interaction took desktop focus. The guard stopped the
review and the temporary app was closed. Full Mac UI and real-device acceptance
remain open. No foreground XCTest was restarted after the automation pause.

## App and checkout

- Checkout: `/Users/colsenmangeris/SayStone-worktrees/mac-workflows`
- Branch: `feat/mac-workflows`
- App: `/Users/colsenmangeris/SayStone-worktrees/mac-workflows/DerivedData/Build/Products/Development/SayStone Development.app`
- Bundle: `com.architech.saystone.development`, version 1.6.10, build 22
- Packaged source: `5f3edae2ecd053b749d6cd288e0e1c06c2b2c84a`
- Private normal data: `~/Library/Application Support/SayStone Development/`
- Swift 5 and macOS 15 support retained; strict deep signature verification passed.

The daily `~/Applications/SayStone.app` was not replaced. No daily settings,
history, clipboard contents or credentials were copied for testing. No shared
speech/profile services, release or push were activated. The separate vocabulary
tokenizer cache limitation below remains open.

## Changes completed

- Clipboard and snippet saves report storage failure truthfully; failed history
  opt-in does not start collection. Privacy reductions still apply in memory,
  retained history expires while collection is off, and UTF-8 limits are enforced.
- Dictation and utility paste use the same bounded clipboard snapshot and
  restoration ownership rules. Cancellation is checked after focus callbacks
  before copy/paste effects. Process timeout/cancellation freezes owned processes
  before termination to prevent a reproduced replacement-child escape.
- Workflows reject pre-cancelled requests, snapshot transcript input once,
  preserve stale external saves and scope delayed cancellation to the correct
  run. App Intent execution respects active-workflow exclusion. Latest ordinary
  dictation remains available with history off, while voice-trigger text remains
  recoverable without replacing the workflow's previous transcript input.
- Flash model downloads now receive an explicit isolated cache destination.
  Readiness and clearing match all three streaming chunk variants. The regression
  fixture rejects both pre-fix cache-path implementations.
- Authored speech acceptance has an opt-in helper with a fresh preferences suite,
  explicit download permission and receipt validation. A skipped-only Xcode run
  returns helper exit 3 and is not accepted. Missing hosted test products are
  rejected before app launch; this check passed against the final packaged app.
- Synthetic test windows now explicitly request presentation and disable
  restoration. A signed temporary review copy now accepts a guarded embedded
  UUID, selects private synthetic data/preferences and skips explicit activation.
  Invalid markers stop before ordinary startup. Normal app behavior and
  foreground CLI UI tests retain their existing paths. Native review confirmed
  workspace launch and search/trim; complete UI acceptance is still pending.

Functional changes are `a08452d` and `e68b756`; native focus/test documentation is
`98289e2`, skip rejection is `9eaed9f`, and synthetic scene startup is `a06056a`.
The missing-test-host preflight is helper-only commit `c9dad5e`.
Background synthetic startup is `dda2bb2`; review-signing/focus safeguards are
`5f3edae`. The standalone fixture runner now includes the startup guard suite.
Three subagents reviewed implementation, receipts and documentation. Changes
are local commits; no remote publication occurred.

## Verification and its limits

| Check | Result |
| --- | --- |
| Final signed Development package at `5f3edae` | Passed; repaired framework, strict deep signature, correct identity/runtime commit, no hosted-test plug-ins |
| Strict SwiftLint 0.63.2 | Last full-project receipt: zero findings across 225 files; changed background-startup Swift files also passed scoped strict lint |
| Missing speech-test host preflight at `c9dad5e` | Rejected the final app-only package before XCTest launch; shell syntax passed |
| Seven standalone synthetic suites | Passed: isolation, guarded synthetic startup in Development/public modes, Flash cache boundary, utility core, clipboard library, workflows and shortcuts |
| Safe hosted native unit tests at `e68b756` | 52 passed, zero failures; includes four new coordinator cases |
| Whisper Tiny authored WAV at `98289e2` | Two repeated final recognitions succeeded; a cached rerun repeated both. Each native receipt has one pass, zero failures/skips |
| Current native Mac UI acceptance | Open: latest XCTest failed four setup checks; native Computer Use at `5f3edae` confirmed workspace/search/trim but stopped after a desktop focus switch |
| Native Computer Use background acceptance | Failed: target activation was recorded during the text/action sequence; temporary app closed and removed after verified exit |
| Parakeet v2 authored inference | Skipped for insufficient 8 GB free; no model download started. Helper correctly returned exit 3 |

The authored Whisper WAV produced `Hello Fluid Voice` on every final. It used
the acceptance-specific Development model directory, with pronunciation
matching disabled and an empty synthetic dictionary. This proves a narrow
file-inference/reset path; it does not prove microphone routing, target-app
insertion, all providers or vocabulary boosting.

Pinned FluidAudio's CTC tokenizer loader still reads its ordinary cache path
even when SayStone uses private CTC models. The reviewed loader does not download
or write there; fully private-cache vocabulary boosting is pending a bounded SDK
follow-up. Daily cache contents were not inspected. Details:
[FLUIDAUDIO-CTC-CACHE-LIMITATION.md](FLUIDAUDIO-CTC-CACHE-LIMITATION.md).

## Next acceptance steps

1. Complete all four utility scenarios on a dedicated test Mac or in an agreed
   uninterrupted window. Background native interaction failed its focus check
   here; do not repeat it on the occupied desktop. See
   [NATIVE-UI-REVIEW.md](NATIVE-UI-REVIEW.md). The iOS simulator cannot run
   SayStone's macOS target.
2. Provide at least the documented 8 GB free before opting into Parakeet model
   download/inference. No personal files were deleted to create space.
3. Test authored microphone audio, routing/hold/toggle/cancel/retry, development
   permissions, global hotkeys, cross-app paste and real Apple Shortcuts discovery
   on a Mac. A passing build does not establish these behaviors.
4. Use the available Mac Mini and iPhone for
   [CROSS-DEVICE-ACCEPTANCE.md](CROSS-DEVICE-ACCEPTANCE.md): confirm profile
   authority, narrow credential scope and activation steps before physical
   route/fallback/cancel/restart checks. Do not seed an empty Development profile
   over the daily profile.
5. Run hosted CI only after an authorized push. Daily installation, shared-service
   activation, publishing and release remain separate decisions.

## Evidence and handoff

[validation/2026-10-11-local-receipts.json](validation/2026-10-11-local-receipts.json)
preserves the package metadata, test counts/failures and revision boundaries.
[validation/2026-10-11-native-review.json](validation/2026-10-11-native-review.json)
preserves the failed focus check and authored functional observations.
The final build log is `/tmp/saystone-native-background-build.log`. Detailed local
receipts and feature status are in
[MAC-UTILITIES-STATUS.md](MAC-UTILITIES-STATUS.md); development commands and the
desktop automation boundary are in [START-HERE.md](START-HERE.md).
Rebuild hosted test products and repair the generated host before using the
speech helper; the final runnable package intentionally has no test plug-ins.

Copyable handoff path:

```text
/Users/colsenmangeris/SayStone-worktrees/mac-workflows/docs/development/MORNING-UPDATE-2026-10-11.md
```
