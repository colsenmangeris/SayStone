# Native Mac review and desktop focus

The October 11 native Computer Use check failed background acceptance. Launch
and action search left the user's active app in place. The subsequent authored
text-entry/Run sequence returned an accessibility error; a fresh AX snapshot
showed the correct trimmed result, but the read-only monitor recorded the review
app becoming active and frontmost. Interactions stopped, scoped Cmd-Q closed the
temporary app, and process exit was verified. The generated temporary app was
then removed while its private receipts were retained. No foreground XCTest was
started.

[Compact receipt](validation/2026-10-11-native-review.json) preserves the source
revision, exact process identity, timestamps, authored result and remaining
scenarios. The first focus switch occurred at 07:34:33 UTC. Source review found
no explicit app activation in the synthetic trim input/action path; the precise
cause is unproven. Use a dedicated test desktop for further native interaction.

## Isolated review preparation

`scripts/local/prepare-native-ui-review.py` prepares a copy and never launches it.
It requires clean production sources, a strictly signed app-only Development
build at current HEAD, the exact Development ID and compiled embedded-session
support. It checks both the executable and Xcode's optional debug dylib. It
rejects ad-hoc signing, stale products and hosted test plug-ins.

```sh
SAYSTONE_REVIEWED_PACKAGE_PLUGINS=1 ./build.sh development
python3 scripts/local/prepare-native-ui-review.py \
  --identity '<exact installed certificate name or SHA-1>'
```

The private temporary copy is named SayStone Native Review. Its executable and
Development bundle ID remain unchanged, and the helper sets `LSUIElement` and a
fresh `SayStoneSyntheticUISession` UUID before re-signing and verifying it. A
0600 receipt gives the exact path, UUID, preference domain, data directory and
named pasteboard. The normal generated app is unchanged by copying.

Embedded synthetic startup requires the Development compile flag, exact
`com.architech.saystone.development` identity and a valid UUID string. Invalid
markers stop before storage/preferences/services initialization. A valid marker
selects the synthetic startup, a UUID preferences suite and temporary utility
data, skipping onboarding, audio/models, Keychain, analytics, API/profile services
and general-clipboard polling. Background startup uses accessory policy, skips
explicit activation and declines reopen. CLI `--ui-testing` remains foreground;
`--ui-testing-background` has no effect without synthetic startup.

The copy shares the ordinary Development permissions identity. Run no other
Development instance, and verify the exact executable PID/path plus embedded
UUID before interacting. Do not use this same-ID copy for real Apple Shortcuts
discovery or App Intent acceptance. It is separate from the daily public app.

## Focus and input boundary

Compile `scripts/local/observe-review-focus.swift` as a standalone Swift CLI and
start it before native CUA launch, using a new private JSONL path and a duration
of at most 1800 seconds. Its `started` record is emitted after subscribing to
activation events. It records only process/focus metadata; no window text,
keyboard input or clipboard contents. It also polls every 250 ms and returns
exit 2 at normal completion if Development ever activated or became frontmost.
Terminate this owned observer after review ends; a terminated run is judged by
its saved records, not an exit-code pass.

Before and after each action, require a live observer, a recent record, no
`finished` marker, `targetEverFrontmost == false`, and exactly one Development
process at the expected review path. Stop interactions immediately if any guard
fails. Close only the confirmed review app and verify exit with read-only process
metadata. Avoid `getApp` or AX discovery after quitting because discovery can
relaunch it. Monitoring does not prevent focus changes, so it cannot make an
unverified controller suitable for an occupied desktop.

All UI actions belong to native CUA. Type or set authored text; do not use native
Copy/Paste commands, Cmd-V or CUA `paste`, which use the general clipboard.
Utility Copy uses the named synthetic pasteboard. Synthetic external actions
must remain rejected. Grant no microphone/Accessibility permissions merely to
exercise these fixtures.

## Remaining authored checks

- Palette: filtered transform, literal padded input, correct output and denied
  external paste. Only search/trim were observed in this review.
- Clipboard Library: history off/empty by default; save/edit literal quotes,
  two dashes and trailing spaces; relaunch preserves the edited snippet.
- Workflows: explicit after-dictation opt-in, saved transform/copy steps,
  completed authored output on the named board, and relaunch persistence.
- Shortcuts: reject bare keys; accept app-local Ctrl-Cmd-J; reject duplicate
  chords without adding a second row. The recorder uses a local key monitor.
  AX value-setting does not prove event capture.

Use a fresh UUID for independent scenarios and the same copied app/UUID for
relaunch persistence. A successful synthetic review still does not establish
microphone routing, permissions, global hotkeys, cross-app paste, real Shortcuts
or cross-device behavior.
