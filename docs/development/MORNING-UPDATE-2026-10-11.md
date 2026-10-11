# SayStone morning update October 11 2026

SayStone's Mac utilities are implemented and received further isolation,
persistence and cancellation fixes overnight. A signed Development app is ready
for review. The latest Mac UI suite is still failing at startup, and real-device
acceptance remains open. Coding and builds resumed after the desktop automation
pause; no foreground UI automation was restarted.

## App and checkout

- Checkout: `/Users/colsenmangeris/SayStone-worktrees/mac-workflows`
- Branch: `feat/mac-workflows`
- App: `/Users/colsenmangeris/SayStone-worktrees/mac-workflows/DerivedData/Build/Products/Development/SayStone Development.app`
- Bundle: `com.architech.saystone.development`, version 1.6.10, build 22
- Packaged source: `a06056ac1806b27bb82dbc3e440aa9cf24c198b4`
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
  restoration. This startup candidate compiles and was reviewed against macOS 15
  APIs; a GUI rerun is still required.

Functional changes are `a08452d` and `e68b756`; native focus/test documentation is
`98289e2`, skip rejection is `9eaed9f`, and synthetic scene startup is `a06056a`.
The missing-test-host preflight is helper-only commit `c9dad5e`.
Three subagents reviewed implementation, receipts and documentation. Changes
are local commits; no remote publication occurred.

## Verification and its limits

| Check | Result |
| --- | --- |
| Final signed Development package at `a06056a` | Passed; repaired framework, strict deep signature, correct identity/runtime commit, no hosted-test plug-ins |
| Latest strict SwiftLint 0.63.2 | Zero findings across 225 files |
| Missing speech-test host preflight at `c9dad5e` | Rejected the final app-only package before XCTest launch; shell syntax passed |
| Six standalone synthetic suites | Passed: isolation, Flash cache boundary, utility core, clipboard library, workflows and shortcuts |
| Safe hosted native unit tests at `e68b756` | 52 passed, zero failures; includes four new coordinator cases |
| Whisper Tiny authored WAV at `98289e2` | Two repeated final recognitions succeeded; a cached rerun repeated both. Each native receipt has one pass, zero failures/skips |
| Current native Mac UI acceptance | Open: initial overnight run passed three of four; latest run failed all four while waiting for the workspace in setup. The `a06056a` startup candidate has no GUI rerun |
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

1. Verify native Computer Use's background behavior in this T3 session, then use
   it for scoped visual checks. Run the complete XCTest UI suite only in an agreed
   uninterrupted window or on a dedicated test Mac. The iOS simulator cannot run
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
The final build log is `/tmp/saystone-morning-scene-build.log`. Detailed local
receipts and feature status are in
[MAC-UTILITIES-STATUS.md](MAC-UTILITIES-STATUS.md); development commands and the
desktop automation boundary are in [START-HERE.md](START-HERE.md).
Rebuild hosted test products and repair the generated host before using the
speech helper; the final runnable package intentionally has no test plug-ins.

Copyable handoff path:

```text
/Users/colsenmangeris/SayStone-worktrees/mac-workflows/docs/development/MORNING-UPDATE-2026-10-11.md
```
