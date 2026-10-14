# SayStone Mac workflows — handoff 2026-10-14

Archive point for T3 thread `6c86838a-97d1-4563-b39d-e5db7662ed19`
("Isolate Development App Data"). A fresh session should start from this
file and [START-HERE.md](../development/START-HERE.md), not from thread history.

## 1. Goal

In the user's words: "Before launching the development app, establish a
separate development identity and data location so testing preserves my daily
SayStone app's settings and history." That expanded, with approval, into
building the planned Mac utilities/workflows on the isolated Development
build, then native acceptance on the MacBook and Mac Mini; the iPhone stage
was deferred by the user.

## 2. Where things are

- This checkout (work happened here): `/Users/colsenmangeris/SayStone-worktrees/mac-workflows`
- Branch: `feat/mac-workflows` — **local only, no upstream, not pushed**
- Main checkout: `/Users/colsenmangeris/SayStone` on `fix/audio-start-recovery`
  (has an unrelated uncommitted `docs/custom/STATUS.md` change; leave it alone)
- Shared-speech checkout: `/Users/colsenmangeris/SayStone-worktrees/shared-speech`
  on `feat/shared-speech-server` at `3b61875` (clean, untouched by this lane)
- Daily app (do not replace): `~/Applications/SayStone.app`, 1.6.10 (22),
  bundle `com.FluidApp.app.debug`
- Start here: `/Users/colsenmangeris/SayStone-worktrees/mac-workflows/docs/development/START-HERE.md`
- Latest status: `/Users/colsenmangeris/SayStone-worktrees/mac-workflows/docs/development/MAC-MINI-ACCEPTANCE-2026-10-13.md`
- Feature status: `/Users/colsenmangeris/SayStone-worktrees/mac-workflows/docs/development/MAC-UTILITIES-STATUS.md`
- Isolation design/evidence: `/Users/colsenmangeris/SayStone-worktrees/mac-workflows/docs/development/DEVELOPMENT-ISOLATION.md`
- UI-test boundaries: `/Users/colsenmangeris/SayStone-worktrees/mac-workflows/docs/development/NATIVE-UI-REVIEW.md`
- Cross-device matrix: `/Users/colsenmangeris/SayStone-worktrees/mac-workflows/docs/development/CROSS-DEVICE-ACCEPTANCE.md`
- Receipts: `/Users/colsenmangeris/SayStone-worktrees/mac-workflows/docs/development/validation/`
- Mini test products (on the Mini): `~/Development/SayStone-Acceptance/20261013-runtime`,
  raw results in `~/Development/SayStone-Acceptance/20261013-results`,
  build volume `/Volumes/ForgeData/SayStone-Acceptance/20261013-e5c8b7b`

## 3. Shipped

Local commits on `feat/mac-workflows` only. No push, PR, deploy, release,
daily-app install, shared-service activation, credential mint/import, or
profile seed occurred. Current tip at archive should be the commit adding
this handoff; prior tip was `d107476`.

- `0d5d461` chore: organize native macOS development workspace
- `3b4a14b` Isolate development identity and local storage
- `5dcfe4e` Add native Mac utilities and isolated acceptance tests
- `8798db8` Verify native acceptance and certificate-free CI
- `a08452d` Harden utility persistence, cancellation, clipboard and model caches
- `e68b756`–`5f3edae` Speech-acceptance helper, synthetic UI startup, focus guards
- `8d98a43` Pin isolated vocabulary tokenizer loading (FluidAudio `bce007d`)
- `40dce45` Fix authored speech helper on macOS Bash 3.2
- `d107476` Record Mini acceptance and unlock prerequisites

Isolated Development identity: **SayStone Development**,
`com.architech.saystone.development`, data under
`~/Library/Application Support/SayStone Development`, separate preferences
domain and Keychain service `com.architech.saystone.development.provider-api-keys`.
Public Debug/Release identities, keys, and paths are unchanged.

## 4. Verified

Recorded in-repo at the commits above; re-read the receipts, do not trust
this summary alone.

- MacBook: signed Development build, strict deep signature
  (`codesign --verify --deep --strict`), seven standalone fixture suites via
  `bash scripts/local/run-mac-utility-fixtures.sh` — see
  `validation/2026-10-11-local-receipts.json`.
- Mini (tested source `8d98a43`): `build-for-testing` passed, app + UI runner
  signed from the GUI session and strictly verified, 52 native units passed
  (0 fail/skip), Whisper Tiny authored WAV passed twice in one native test
  (0 fail/skip) — see `validation/2026-10-13-native-acceptance.json`.
- FluidAudio SDK cache fix pinned at `bce007d`; two SDK tokenizer tests with
  real CTC 110M assets passed — see `validation/2026-10-13-ctc-cache-sdk.json`
  and `FLUIDAUDIO-CTC-CACHE-LIMITATION.md`.
- At archive (2026-10-14): `git status` was clean before this handoff edit;
  no stashes in this worktree.

## 5. Not verified

- All four utility UI scenarios: on the Mini the runner timed out enabling
  automation ("Timed out while enabling automation mode") before any
  scenario ran. Counts: Utilities 0 passed / 1 runner failure. A build or
  unit pass does not accept these scenarios.
- Live microphone routing (Mini reported 0 audio-input devices), global
  hotkeys, cross-app paste/insertion, real Apple Shortcuts, cancellation/
  recovery with real capture, Parakeet inference (below the 8 GB gate),
  vocabulary-boosted inference, and background Computer Use (failed its
  focus check on 2026-10-11).
- iPhone / profile / shared-speech acceptance: deferred; see
  `CROSS-DEVICE-ACCEPTANCE.md`. Hosted CI has not run (branch never pushed).
- Whether the Mini desktop was ever unlocked after the last check, and
  whether the temporary Screen Sharing tunnel is still up.

## 6. Open items

1. Get a ~15-minute unlocked Mini desktop window. Verify or recreate the
   loopback tunnel (`vnc://127.0.0.1:15900`; see MAC-MINI-ACCEPTANCE-2026-10-13
   "Resume prerequisites"), have the user authenticate in Screen Sharing
   (never in chat), then on the Mini run
   `sudo /usr/sbin/DevToolsSecurity -enable`. Do not change lock settings.
2. Re-verify both Mini signatures, then rerun only the four `SayStoneUITests`
   utility scenarios (synthetic paste denial; snippet save/edit/relaunch;
   workflow transform/copy/persistence; shortcut capture/conflict). No rebuild
   is needed for unchanged `8d98a43` app code. Record a new receipt.
3. Connect a microphone to a test Mac; run authored live capture, hotkey,
   cross-app paste, cancellation/recovery, and real Shortcuts checks.
4. Only with explicit authorization: push `feat/mac-workflows`, open a PR, and
   run hosted CI. Daily-app install and release are separate decisions.
5. Resume the deferred phone/profile stage only per
   `CROSS-DEVICE-ACCEPTANCE.md` (profile authority and narrow
   `speech:operate` credentials first; never seed an empty Development
   profile over the daily profile).

## 7. Decisions

- Development isolation is a compile-time configuration (`SAYSTONE_DEVELOPMENT`),
  not launch flags, so opening the built app directly is safe. Rejected:
  bundle-ID-only isolation (shared paths/Keychain leaked).
- Utilities are opt-in: no utility hotkey, voice phrase, post-dictation
  workflow, or clipboard-history collection is on by default. Workflows use
  typed, bounded, cancellable actions, not model-generated shell commands.
- FluidAudio fix lives in the SDK fork and is pinned; rejected: symlinking or
  borrowing the ordinary cache as a workaround.
- UI automation runs only on a dedicated/uninterrupted desktop after the
  2026-10-11 focus-switch failure; rejected: treating source guards as proof
  of background safety.

## 8. Gotchas

- Mini SSH: Tailscale IPv6 `fd7a:115c:a1e0::ff39:b618` with
  `HostKeyAlias=100.97.182.23` worked; saved IPv4 timed out (cause unknown).
- Direct SSH signing failed with `errSecInternalComponent`; sign from the
  logged-in GUI session. ForgeData builds hit removable-volume restrictions;
  the documented CI ad-hoc flags plus internal-storage signing are the known
  path (see MAC-MINI-ACCEPTANCE-2026-10-13).
- Last recorded Mini check: desktop locked (`IOConsoleLocked` true) and
  Developer Tools mode disabled. The automation timeout does not prove each
  factor's share. Screen Sharing was running; the user could not screen-share
  at that moment, so a local SSH tunnel was opened for them.
- Speech helper exit `3` means skipped/not-accepted even if `xcodebuild`
  exits 0. Rebuild with `build-for-testing` and repair CTranscribe before
  rerunning speech or UI tests (see START-HERE).
- Xcode 27 beta / Swift 6.4 on both Macs; deployment target stays macOS 15,
  language mode stays Swift 5. Package.swift is not the app build entrypoint;
  `SayStone.xcodeproj` / `./build.sh` is.
- Never inspect daily transcripts, clipboard history, credentials, or profile
  payloads to test. Use authored fixtures and named pasteboards.
