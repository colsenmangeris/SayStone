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

## Completion record

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
- Final signed build, native smoke results and real microphone/permission/
  cross-app/device receipts belong to root's integrated validation record.
  Fixture results do not establish those native behaviors. Cross-device
  acceptance remains documented separately in CROSS-DEVICE-ACCEPTANCE.md.

## Boundaries

No private transcript, clipboard-history or credential inspection is needed for
testing. Clipboard history remains off until explicitly enabled by the user.
Ordinary workflows contain typed fixed actions, not generated shell commands.
Production app replacement, shared-speech service activation, push, publication
and release require their own task authorization after the result is reviewable.
