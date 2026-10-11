# SayStone Mac utilities: implementation and acceptance

Date: 2026-10-10. Checkout:
`/Users/colsenmangeris/SayStone-worktrees/mac-workflows`, branch
`feat/mac-workflows`. The isolation baseline is commit `3b4a14b`.
The feature implementation is commit `5dcfe4e`; subsequent local commits contain
final permission guidance, CI verification and these acceptance receipts.
Implemented features are distinct from real-device acceptance.

## Runnable development app

`/Users/colsenmangeris/SayStone-worktrees/mac-workflows/DerivedData/Build/Products/Development/SayStone Development.app`

Bundle ID: `com.architech.saystone.development`. The normal development data
root is `~/Library/Application Support/SayStone Development/`; preferences,
Keychain service, model/cache paths, recovery audio and history are separate
from the daily app. Updates and rollback installation are blocked in this
identity. No daily settings/history were copied into development. The daily
`~/Applications/SayStone.app` was not replaced or reconfigured.

Build using the native shared SayStone scheme, My Mac, Development, Swift 5,
macOS 15 deployment support. See [START-HERE.md](START-HERE.md) for package-plugin
approval and generated-framework repair. Xcode MCP was unavailable for this run;
native Xcode CLI builds and XCTest supplied the build/test evidence.

## Implemented

- One typed action registry connects the searchable palette, menu, configurable
  utility keyboard shortcuts, workflow execution and suitable App Intents.
  Actions include copy latest transcript, plain-text paste, copy/paste supplied
  text, deterministic transformations, snippets, URLs, apps and named Apple
  Shortcuts. Parameters are bounded data, not generated shell source.
- Utility shortcuts retain existing dictation assignments, reject conflicts,
  support an optional app scope and suppress repeats. A later settings change
  that creates a conflict disables matching at runtime. Utility shortcuts wait
  for modifier release and revalidate their captured target before execution.
- Plain-text paste validates the exact captured field and frontmost app. It
  preserves materialized clipboard formats and restores only its own clipboard
  generation. Utility and dictation paste share a transaction lock through
  restoration. Paste dispatch is not proof that a target app inserted the text.
- Pinned snippets can be created, edited, searched, copied or inserted. Local
  transforms have an explicit preview. Literal utility editors reuse the
  existing AppKit text editor without automatic substitutions.
- Clipboard history starts off. Opt-in skips the existing clipboard before
  polling new changes; retention, count/text/storage bounds, clear controls and
  app exclusions are explicit. Concealed, transient and generated clipboard
  markers are checked before text access. Unmarked background copies cannot
  always be attributed accurately; the UI explains this limitation. JSON is
  private (`0600`, directory `0700`); malformed/future files are preserved.
- Workflows have versioned local storage, ordered typed steps, fixed/previous/
  latest-transcript input, run/step deadlines, cancellation, progress and step
  results. Exact voice phrases and post-dictation selection are off by default.
  One saved workflow may explicitly replace normal automatic delivery after
  dictation. A Paste text step delivers its output. Recognized text remains in
  SayStone's editor and, when enabled, history before the workflow runs; failure
  or cancellation does not replay completed effects or ordinary delivery.
- App Intents expose local transforms, copying the latest transcript, opening
  utilities and saved workflow execution. Intent workflows reject paste steps
  before running because there is no captured target field. Named Apple
  Shortcuts receive separate process arguments and optional private text files;
  a visible confirmation precedes execution. Cancellation cannot undo effects
  already performed inside Apple's Shortcuts service.
- Existing advanced command mode now honors its confirmation preference for
  every shell command, with bounded output, timeout and cancellation. Existing
  provider choices and microphone settings are retained.
- Development-only synthetic startup, stable accessibility IDs and native
  smoke tests make the new surfaces testable. CI runs isolated fixtures and
  selected safe hosted units, compiles UI tests, preserves results and pins its
  reviewed MLX plugin exception. Strict lint's 52 inherited findings were fixed without broad rule
  suppression. The [fork policy](UPSTREAM-POLICY.md) requires explicit upstream
  review and adoption; no automatic merge or release was introduced.

## Validation receipts

Integrated native results are recorded below. Fixture and
build success do not prove microphone routing, macOS permission behavior,
global hotkeys or cross-app delivery.

| Check | Evidence |
| --- | --- |
| Five utility/isolation fixture suites | Passed; `/tmp/saystone-final-utility-fixtures.log` |
| Affected speech/request/recovery regression fixtures | Passed; dictation API/cleanup, engine digests, profile protocol, MAI request encoding, recovery WAVs and audio-start deadlines |
| Full strict SwiftLint 0.63.2 | Zero findings; `/tmp/saystone-swiftlint-root-latest.json` |
| CI workflow syntax | Actionlint 1.7.12 passed; hosted jobs have not run |
| Signed Development and test-target build | Passed; `/tmp/saystone-utilities-candidate-build.log`, `/tmp/saystone-utilities-candidate-test-build.log` |
| Strict deep signature | Passed after generated-framework repair; `/tmp/saystone-utilities-signature-repair-candidate.log` |
| Four native utility smoke scenarios | All passed; `/tmp/SayStone-Utilities-Candidate.xcresult`, `/tmp/saystone-utilities-native-candidate.log` |
| Selected safe native unit tests | 48 passed with zero failures in the same result bundle |
| Local certificate-free CI path | Ad-hoc build/repair/strict verification and 48 hosted units passed; `/tmp/SayStone-Utilities-AdHocBuildFixed.xcresult`, `/tmp/SayStone-Utilities-AdHocUnits.xcresult` |

The four UI cases cover palette search/transform and synthetic external-action
denial, shortcut validation/conflicts, snippet create/edit/relaunch persistence
with history off, and workflow transform/copy/relaunch persistence with explicit
post-dictation selection. Literal inputs include straight quotes, double hyphens
and two trailing spaces; tests compare actual editor and output values.

The certificate-free check also verified the generated Development test-host
paths, deterministic startup and retained library-validation entitlement.
An attempted ad-hoc UI execution was stopped after macOS AMFI rejected the
UI runner's launch (`Code=-423`), although its strict signature check passed.
It is not a UI pass. CI compiles UI tests; their execution remains a signed
local gate. The trusted Development-certificate run above passed all four.
Hosted CI itself remains unexecuted because this branch has not been pushed.

Native UI fixtures use a fresh UUID preferences domain and temporary utility
folder, a named synthetic pasteboard and authored strings. Their startup skips
audio/models, general-clipboard history polling, Keychain, onboarding,
analytics and local API/profile services. External actions are rejected in
synthetic mode. Tests validate actual input values and rendered results; no
private dictation, clipboard history or credentials were inspected.

## Remaining acceptance and next actions

1. Use the isolated development app for authored microphone tests: built-in and
   Bluetooth routing, hotplug, sleep/wake, hold/toggle, cancellation, recognition
   retry and raw fallback. Its separate identity needs its own macOS permissions.
2. Grant the development app Accessibility only for the reviewed native test
   stage. Verify configured global shortcuts, denied permission, exact-field
   changes, several target apps, clipboard restoration and concurrent copying.
   Existing daily permission grants are not development acceptance.
3. Discover and execute the App Intents in the real Apple Shortcuts app, check
   named-shortcut output/cancellation, and repeat compatibility on macOS 15.
4. Follow [CROSS-DEVICE-ACCEPTANCE.md](CROSS-DEVICE-ACCEPTANCE.md). The user has
   confirmed Mini/iPhone availability; read-only readiness is refreshed. The
   installed Forge release source and narrow auth issuer are now verified.
   Operator/data-root confirmation, selected initial profile authority, narrow
   credentials, authorized seed/sync activation and physical
   route/fallback/cancel/retry/restart/concurrency receipts remain outstanding.
   Keep NeMo and Qwen TTS through acceptance. Do not overwrite the shared profile
   with an empty development profile.
5. Run the updated hosted CI against an explicitly authorized push. Production
   installation, deployment, service activation, publication and releases are
   separate actions, as required by [BUILD-PROMPT.txt](BUILD-PROMPT.txt).

The local implementation does not require personal data to validate it. The
next live stage requires the relevant permission/activation authorization and
device coordination, not secrets pasted into chat.
