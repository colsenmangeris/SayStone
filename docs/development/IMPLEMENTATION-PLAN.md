# Mac utility implementation and acceptance

This branch extends the existing SayStone app in place. Development builds use
the isolated identity and paths documented in DEVELOPMENT-ISOLATION.md. The daily
installation is not an implementation or test target.

## Sequence and ownership

1. Preserve the signed isolated baseline and its fixture checks.
2. Add one typed action registry used by the palette, menu, configurable keyboard
   shortcuts and workflows. Copy latest transcript is the first integration;
   plain-text paste revalidates the captured target and preserves pasteboard data.
3. Add pinned snippets, deterministic text transforms and explicitly enabled
   clipboard history with bounded retention, clearing and source exclusions.
4. Add versioned deterministic workflows, bounded cancellable execution, explicit
   voice phrases and native Apple Shortcuts integration.
5. Add deterministic development-only UI test startup, stable accessibility
   identifiers and native smoke coverage. Strengthen CI and document upstream
   update policy alongside the feature work.
6. Complete local native checks and prepare the separate shared-speech acceptance
   run. Mac Mini/iPhone availability and shared-service activation are external
   acceptance boundaries; neither a build nor a fixture proves them.

Root owns integration, project/build configuration, existing shortcut/paste paths,
native tests, CI and this record. Dedicated agents own new utility core,
clipboard-library and workflow source files with synthetic fixture suites.
Xcode builds and generated-framework repair are serialized by root.

## Feature and test map

| Feature | Implementation | Verification |
| --- | --- | --- |
| Development identity/data isolation | AppStorage, Development configuration | Separate bundle, data/model paths, Keychain service; daily sentinel untouched |
| Typed actions and transformations | UtilityAction registry | Invalid inputs, bounded sizes, deterministic Unicode fixtures |
| Plain-text paste | UtilityClipboard + existing focus service | Unique test pasteboard, format preservation, changed-target rejection, concurrent-copy preservation |
| Named Shortcuts/process execution | UtilityProcessRunner | Argument boundaries, pipe draining, output bound, timeout and cancellation |
| Configurable shortcuts | Utility settings + existing global event manager | Conflicts with dictation/cancel/prompt, repeat suppression, app scope |
| Snippets/history | ClipboardLibrary | Opt-in default, excluded markers/apps, bounded retention, clearing, persistence |
| Workflows | UtilityWorkflow/Store/Runner + native step editor | Input propagation including named Shortcut input, validation, cancellation, bounded deadlines, malformed recovery/newer-schema preservation, exact opt-in voice matching |
| Post-dictation workflow | Explicit saved selection + existing dictation output path | Version-1 missing-field compatibility, off by default, one active selection with persisted switching; recognized text retained before workflow-owned delivery |
| Native surfaces | Palette, library and editor | Stable accessibility IDs, native UI smoke tests, synthetic startup |
| Regression | Existing speech/history services | Relevant fixture suites and signed Development build |
| Real Mac behavior | Development installation only | Focus, Accessibility, global hotkey, cross-app paste; authored text/audio |
| Shared speech | Existing cross-device handoff | Fresh device receipts, vocabulary/tombstones, cancellation, fallback and restart |

## Completion record: 2026-10-10 candidate

- Isolated signed Development build and standalone isolation/history/recovery
  fixtures passed before utility implementation. Daily app was not launched or
  replaced.
- Workflow definitions, native add/configure/reorder/remove editor, run/cancel
  progress and per-step results are implemented. Definitions remain local and
  versioned; bounds are 100 definitions, 24 steps, 1 MiB text, 4 MiB storage,
  120 seconds per run and 30 seconds per step. Deadline/cancellation fixtures
  confirm no late results or later steps after cancellation or timeout.
- Post-dictation execution is an explicit opt-in. Saving a selection disables
  the previous selection. Existing version-1 definitions without that optional
  field remain off. The existing recognition path sets SayStone's editor and,
  when enabled, history before invoking the selected workflow with recognized
  text and the captured target. The workflow replaces ordinary automatic
  delivery: a **Paste text** step explicitly inserts its output. Failure,
  cancellation or a busy runner leaves recognized text in SayStone without
  replaying ordinary paste/copy or completed workflow effects. Core recognition
  providers, microphone capture and default dictation behavior remain intact
  when no workflow is selected.
- All five synthetic utility/isolation fixture suites pass through
  `bash scripts/local/run-mac-utility-fixtures.sh`. Workflow Swift files also
  pass Swift 5 typechecking with the app's MainActor default. Full strict
  SwiftLint 0.63.2 passes after mechanical cleanup of the initial 52 baseline
  violations. The CI workflow passes Actionlint; hosted execution awaits an
  authorized push.
- Signed Development and test-target builds passed. After generated-framework
  repair, strict deep signature verification passed. All four native utility
  smoke scenarios and 48 selected safe hosted unit tests passed with zero
  failures in `/tmp/SayStone-Utilities-Candidate.xcresult`. Native tests check
  rendered values, literal text preservation and same-session relaunch
  persistence. Details and runnable app location are in MAC-UTILITIES-STATUS.md.
  Real microphone/permission/cross-app/device acceptance remains outstanding;
  fixtures and synthetic startup do not establish those behaviors.
  CROSS-DEVICE-ACCEPTANCE.md records current Mini/iPhone readiness and the
  verified installed Forge release/source and narrow credential issuer.
- The local certificate-free CI command sequence also passed: ad-hoc native
  build, framework repair, strict deep verification and 48 selected hosted
  units (`/tmp/SayStone-Utilities-AdHocUnits.xcresult`). CI preserves package
  language modes and compiles UI tests; macOS AMFI rejected the ad-hoc UI
  runner's launch. Signed UI execution remains a local gate and already passed
  above. Platform security was not disabled and no signing secrets were added.
- Final runnable Development packaging at functional code commit `8798db8`
  passed through the signed build helper, including framework repair and strict
  deep verification. Bundle identity, macOS 15 minimum and runtime commit were
  verified. No daily app installation or private-data copy occurred.

## Overnight hardening and acceptance: 2026-10-11

The overnight check sequence ran through `9eaed9f`. Functional hardening landed in `a08452d`
and the voice recovery lookup correction in `e68b756`. The smoke-test focus
change is `98289e2`; the authored-speech helper's skip rejection is `9eaed9f`.
The October 10 completion record above remains evidence for its original
candidate, not acceptance of these later revisions.

- Workflows snapshot latest transcript before steps and before saving a voice
  trigger. They reject pre-cancelled starts and expose a run identifier for
  scoped cancellation, so an older delayed handler cannot cancel a newer run.
  Completed effects are retained without replay. Store reads are bounded;
  stale-save detection preserves external changes and offers a reload while
  retaining the current draft. Metadata comparison does not implement a
  cross-process file lock.
- Guarded App Intent copy execution respects in-flight utility/workflow
  exclusion. The coordinator retains literal current dictation in memory even
  with history disabled; voice-trigger recovery retains the recognized phrase
  in SayStone while preserving the previous ordinary transcript as workflow
  input. Four new isolated native coordinator cases verify these local paths
  with authored strings and a named test pasteboard.
- Clipboard storage and transaction ownership received further failure,
  retention and cancellation coverage. Flash provider model download now
  receives the isolated cache root explicitly, and readiness follows the
  selected chunk variant. Its new boundary fixture checks routing and readiness
  without performing a real network download or speech inference.
- Six synthetic suites passed in `/tmp/saystone-overnight-fixtures.log`;
  the scoped-cancellation regression passed in
  `/tmp/saystone-overnight-workflow-lease.log`. Strict SwiftLint reported zero
  findings in `/tmp/saystone-overnight-lint.json`.
- Signed build-for-testing passed at `e68b756` and again at `98289e2`, recorded
  in `/tmp/SayStone-Overnight-Build-Fixed.xcresult` and
  `/tmp/SayStone-Overnight-FocusBuild.xcresult`. The overnight functional native
  run passed 52 safe hosted units with zero failures in
  `/tmp/SayStone-Overnight-Native.xcresult`.
- Current UI acceptance is **open**. The initial overnight run passed three of
  four scenarios; palette/transform failed after losing the utility window.
  The latest focus-adjusted run failed all four during setup, before accepting
  their scenarios (`/tmp/SayStone-Overnight-FocusUI.xcresult`). Investigate that
  setup and repeat the complete signed suite; the earlier four-of-four pass
  does not cover these revisions.
- Actual Whisper Tiny inference on the authored repository WAV passed two
  consecutive finals in the initial native test and two more in a cached
  rerun. Each receipt contains one passed native test, zero failures/skips:
  `/tmp/SayStone-Overnight-Whisper.xcresult` and
  `/tmp/SayStone-Overnight-Whisper-Cached.xcresult`. This is narrow base-model
  acceptance, not microphone or all-provider acceptance.
- Parakeet V2 remains unaccepted: its test skipped for insufficient 8 GB disk
  headroom. The revised helper returned exit 3 rather than presenting that skip
  as acceptance (`/tmp/SayStone-Overnight-Parakeet-Guard.xcresult`). Pinned
  FluidAudio's vocabulary tokenizer still selects an ordinary cache path;
  private-cache vocabulary boosting remains pending the source-reviewed
  dependency follow-up in
  [FLUIDAUDIO-CTC-CACHE-LIMITATION.md](FLUIDAUDIO-CTC-CACHE-LIMITATION.md).

Full receipt paths and current remaining actions are in
[MAC-UTILITIES-STATUS.md](MAC-UTILITIES-STATUS.md). Hosted CI,
microphone/permission/cross-app checks and cross-device profile/auth/physical
acceptance remain separate gates. No daily installation or shared service was
changed by this overnight validation.

### Background continuation after the desktop automation pause

Commit `a06056a` adds explicit presentation and disables window restoration only
for synthetic Development startup. Normal launches keep SwiftUI's automatic
behavior. The latest UI log showed no accessible workspace/window, so this is
a bounded candidate for the startup gap; the actual restoration trigger remains
unproven. Both scene APIs support macOS 15 in Apple's documentation and the
installed SDK. Strict SwiftLint remains at zero findings. No GUI suite was run
to validate this candidate after the foreground automation pause.

The final signed app build passed at `a06056a` using `./build.sh development`;
the helper repaired the generated framework and strict deep verification passed.
The bundle records runtime commit `a06056ac1806b27bb82dbc3e440aa9cf24c198b4`,
macOS minimum 15.0, and no hosted-test plug-ins. Log:
`/tmp/saystone-morning-scene-build.log`. Compact receipts and the morning handoff
are preserved in [validation/2026-10-11-local-receipts.json](validation/2026-10-11-local-receipts.json)
and [MORNING-UPDATE-2026-10-11.md](MORNING-UPDATE-2026-10-11.md).

Helper-only commit `c9dad5e` rejects missing or unexpected hosted test bundles
before launching XCTest. The negative preflight passed against the final app-only
package, which intentionally omits plug-ins. Rebuild native test products and
repair the generated host before using the authored speech helper again.

## Boundaries

No private transcript, clipboard-history or credential inspection is needed for
testing. Clipboard history remains off until explicitly enabled by the user.
Ordinary workflows contain typed fixed actions, not generated shell commands.
Production app replacement, shared-speech service activation, push, publication
and release require their own task authorization after the result is reviewable.
