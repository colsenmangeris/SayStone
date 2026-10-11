# SayStone fork updates and acceptance

The personal fork is `colsenmangeris/SayStone`; the upstream source is
`altic-dev/FluidVoice`. The feature checkout is
`/Users/colsenmangeris/SayStone-worktrees/mac-workflows` on `feat/mac-workflows`.
The recovery and shared-speech worktrees have separate owners and purposes.
An upstream change is a candidate until reviewed and accepted locally.

## Review without changing the active app

1. Check the selected checkout's branch and Git status. Record its HEAD and the
   current `SayStone.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
   Leave unrelated local changes in their owner's checkout.
2. Fetch upstream refs only when a review is requested, recording the exact
   commit SHA. Fetching updates Git refs; it does not install or release an app.
   Inspect source, dependency pins, licensing, migrations and release notes.
3. Create a separate review worktree from the accepted personal baseline. Apply
   only the requested candidate commits there. Resolve conflicts explicitly,
   preserving SayStone's identity, tagline, providers, Keychain names and daily
   settings/storage keys. Keep Swift 5 mode and macOS 15 unless separately
   authorized to change compatibility.
4. Use the isolated Development configuration for builds and native tests.
   Re-review changed package plugins before trusting them. CI's per-invocation
   MLX plugin allowance is limited to the pinned revision recorded in the
   workflow; changing its pin requires reviewing that plugin and updating the
   allowance deliberately. Do not set a global plugin-trust preference.
5. Record the candidate SHA, changed pins, conflicts, validation evidence and
   unresolved acceptance checks. Merging, pushing, replacing the daily app,
   enabling shared speech and releasing require their own task authorization.

Use `gh-axi` with `-R colsenmangeris/SayStone` for personal-fork operations;
the CLI's repository inference can otherwise select the inherited upstream.
Register any PR being worked on with the T3 thread's PR-linking tool. No
automatic upstream merge or release is configured here.

## Local and hosted checks

Run the self-contained fixture entrypoint from this checkout:

```sh
bash scripts/local/run-mac-utility-fixtures.sh
```

It runs development-storage boundaries, typed actions/subprocesses, clipboard
privacy/retention, workflow propagation/cancellation/deadlines and utility
shortcut-conflict fixtures. Each uses authored data, temporary files or uniquely
named pasteboards. It does not read personal dictation or the general clipboard
and does not launch the installed daily app.

`.github/workflows/build.yml` runs on `main` and `feat/mac-workflows` pushes,
non-draft PR updates against those branches, and manual dispatch. Build-affecting
paths include the native project, package pins, `build.sh`, source, tests and
local build/test helpers. Manual dispatch bypasses the changed-path filter.
The Mac job selects the latest stable Xcode, explicitly builds Development in
the native project, compiles `SayStoneUITests`, runs synthetic fixtures and
executes only the named safe hosted unit tests. It caches package
sources under this checkout's `DerivedData/SourcePackages`; it does not populate
the daily app's model directories. Logs and `.xcresult` bundles are retained for
14 days, including failed runs.

The app and native test targets retain their project-defined Swift 5 language
mode and macOS 15 deployment floor. CI preserves each pinned Swift package's
compiler mode, feature flags and platform declaration. Global command-line
`SWIFT_VERSION` or `MACOSX_DEPLOYMENT_TARGET` overrides also reach package targets
and must be omitted. A local CI-command check demonstrated this boundary:
forcing `SWIFT_VERSION=5` made pinned Jinja 2.3.5
(`0aeefadec459ce8e11a333769950fb86183aca43`) fail parsing bare-slash regular
expressions in `Filters.swift` and `Template.swift`. Its manifest uses Swift 6
package tools and declares macOS 13. Its own settings can coexist with the
SayStone app's Swift 5/macOS 15 settings.

Native CI first runs `build-for-testing` with manual ad-hoc signing and no team
certificate. Xcode signs the host and test products while retaining the app's
declared entitlements. The existing framework repair helper then fixes only the
generated Development app's `CTranscribe.framework`, signs with identity `-`,
and checks `codesign --verify --deep --strict` before any host launches. Starting
with signing disabled would leave no existing app entitlements for the helper
to preserve when it enables hardened runtime. In particular, the inherited
disable-library-validation entitlement supports loading test code.
[Apple's library-validation documentation](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.disable-library-validation)
describes that runtime requirement.

The test phase runs `test-without-building` against the exact `.xctestrun`
produced by that build, preserving repaired products rather than rebuilding
them. CI validates that the manifest names the Development host, its
`--ui-testing` startup argument, and the compiled Development UI-test target.
Execution uses explicit hosted-unit filters and disables parallel testing.
Build and test phases have separate logs and `.xcresult` bundles;
repair/verification logs are retained too. These split actions follow
[Apple's command-line testing workflow](https://developer.apple.com/library/archive/technotes/tn2339/_index.html).
An ad-hoc CI signature verifies generated structure and integrity; it does not
establish installed Developer ID/notarization acceptance, stable daily-app
permissions, or real microphone/hotkey/paste behavior. Hosted execution remains
pending until an authorized push/dispatch produces a passing receipt.

The local ad-hoc check built both test targets, repaired the framework, passed
strict deep verification, retained disable-library-validation, and completed
the 48 selected hosted units. macOS then rejected the exact generated UI-runner
executable through AMFI with `Code=-423`, "The file is adhoc signed or signed
by an unknown certificate chain". The UI runner's own strict signature check
passed; integrity verification did not establish launch trust. That combined
attempt was stopped and does not count as an ad-hoc UI-test pass.
A separate hosted-unit-only invocation then completed successfully with all 48
tests and zero failures in `/tmp/SayStone-Utilities-AdHocUnits.xcresult`, matching
the final CI execution filters. The successful build receipt is
`/tmp/SayStone-Utilities-AdHocBuildFixed.xcresult`.

CI therefore compiles UI tests and executes the 48 hosted units with ad-hoc
products. Native UI execution requires a trusted Apple Development identity;
the locally signed candidate passed all four UI smoke tests and the same 48
selected units. Keep that signed native UI run as an adoption/release gate.
CI does not add signing secrets or certificates, and does not disable AMFI,
SIP, TCC or other platform security to run UI tests.

Strict SwiftLint remains a separate check using the inherited rules. The native
build runs independently so existing lint debt cannot suppress compilation
evidence. A successful build never turns a failing lint check into acceptance;
fix or explicitly review the actual lint findings before merging. No blanket
rule suppression is introduced for new feature work.

The 2026-10-10 local baseline check used the official SwiftLint 0.63.2 portable
binary against an archived copy of committed baseline
`3b4a14b83dc4c11fd20d7e105e4667a0c1e4a7b4`. It reported 52 strict violations,
including force casts/unwraps, argument formatting and collection checks in
existing request, recovery and speech-profile fixtures/services. Those findings
were then fixed with guarded fixture parsing, safe literal construction and
formatting changes. The current 2026-10-10 feature checkout passes the same full
strict scan with **zero violations**. Speech-profile enrollment absence retains
one narrowly documented collection-rule exception to preserve its wire schema.
Affected synthetic suites pass for dictation API/cleanup, engine digests, speech
profiles, MAI request encoding, recovery WAVs, audio-start deadlines and
development-storage isolation. These local receipts do not claim hosted CI has
executed; repeat checks against the exact candidate commit before adoption.

This policy and workflow are local changes until pushed with authorization.
Do not describe unexecuted GitHub jobs as passing hosted CI.

## Native acceptance before adoption

- Repair generated `CTranscribe.framework` with the existing helper and verify
  the development app with `codesign --verify --deep --strict` when packaging.
- Verify real recording, processing and delivery with authored phrases using
  built-in and Bluetooth microphones, device changes, hotplug and sleep/wake.
  Exercise hold/toggle shortcuts and conflicting assignments.
- Check raw transcript retention, recoverable failures/retry, model readiness,
  cancellation and cleanup fallback. Compare names, numbers, identifiers and
  explicit corrections against the authored phrase.
- Verify post-dictation workflows remain off for existing definitions. When
  explicitly selected, the workflow owns delivery and a Paste text step is
  required for insertion. Fail or cancel after a completed step: recognized
  text must remain in SayStone without repeating automatic delivery or earlier
  effects. Turn the selection off and confirm normal dictation delivery returns.
- Check native Accessibility denial, target changes during processing, plain
  text insertion in several apps, supported-format clipboard restoration and
  concurrent copying. UI smoke tests do not grant real permission acceptance.
- Discover and run the intended App Intents in Apple's Shortcuts app, including
  macOS 15. Verify named Apple Shortcut cancellation and execution results.
- For shared speech, follow the canonical cross-device handoff with separately
  authorized Mac/Mini/iPhone access. Credential bootstrap, profile authority,
  synchronization, final-only audio transport, cancellation/retry and terminal
  receipts remain device acceptance, not consequences of a passing Mac build.

Adoption requires an explicit result for each relevant check, the exact candidate
SHA and app path, a strict-signature receipt and known limitations. Production
replacement/release is a separate final action against that reviewed candidate.

References: [GitHub workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax),
[hosted runner specifications](https://docs.github.com/en/actions/reference/runners/github-hosted-runners),
[artifact upload behavior](https://github.com/actions/upload-artifact).
