# Mac Mini acceptance — October 13, 2026

The isolated Development app and UI runner compile on the Mini and pass strict
deep signature verification with its Apple Development certificate. All 52
reviewed native unit tests passed. Whisper Tiny recognized the authored WAV
twice in one passing native test, with zero failures or skips. Utility UI
acceptance remains pending: the runner timed out while enabling automation,
before any of the four feature scenarios ran. The desktop had locked and
Developer Tools mode was disabled at the post-run check.

The SDK cache fix is published and pinned. The phone stage is deferred at the
user's request. Microphone routing remains blocked by absent input hardware;
the Mini currently reports only its speakers. No daily app/data replacement,
shared-speech activation, profile seed, credential import or app release occurred.

## Revisions and isolation

- Tested app source: `8d98a433257b9ccb46c3448bd08565ce8713918b`.
- SDK: [`bce007d1c1b559f2f224bb1369bd1fc7c95fbc7a`](https://github.com/colsenmangeris/FluidAudio/commit/bce007d1c1b559f2f224bb1369bd1fc7c95fbc7a).
- Speech-helper portability fix: local commit `40dce45`.
- Bundle: `com.architech.saystone.development`, version `1.6.10 (22)`.
- Deployment target: macOS 15; app language mode remains Swift 5.
- Synthetic tests use UUID preference suites, temporary utility directories and
  named pasteboards. Onboarding, audio capture, provider Keychain access,
  clipboard collection and API/profile services remain skipped.
- Ordinary Development data is under
  `~/Library/Application Support/SayStone Development`. No daily data or models
  were copied into it. Whisper assets are in its authored-acceptance directory.

## Confirmed checks

| Check | Current result |
| --- | --- |
| Seven standalone authored fixture suites on the MacBook | Passed without app launch |
| SDK tokenizer-directory tests | Two passes using separately provisioned real CTC 110M models; no inference |
| Mini native `build-for-testing` | Passed with the existing CI ad-hoc compilation flags |
| Final Mini app and UI-runner signatures | Trusted Apple Development signatures; strict deep verification passed |
| Reviewed native unit filters | 52 passed, zero failures/skips |
| Whisper Tiny authored WAV | One native test passed; two repeated final recognitions; zero failures/skips |
| Four utility UI scenarios | No feature checks executed; runner initialization failed with automation timeout |
| Parakeet file inference | Not run in this stage; internal storage is below the 8 GB download gate |
| Microphone routing | No audio-input device detected; no microphone capture attempted |
| Global hotkeys, cross-app insertion, real Shortcuts | Pending real native acceptance |
| iPhone | Paired physical device reported unavailable; user deferred phone testing |

Compact native receipt:
[validation/2026-10-13-native-acceptance.json](validation/2026-10-13-native-acceptance.json).
SDK provenance and tests:
[validation/2026-10-13-ctc-cache-sdk.json](validation/2026-10-13-ctc-cache-sdk.json).

## Mini environment and generated products

SSH works over the Mini's Tailscale IPv6 address with its existing host key.
The saved IPv4 SSH address continued to time out; the underlying cause is not
established. Forge's private health route and Tailscale probes respond.

The Mini uses Xcode 27.0 (`27A5252f`), Swift 6.4 and macOS 26.6.2. The missing
Metal Toolchain was installed through Xcode's supported component command.
Its existing source checkout at `~/development/saystone` was left unchanged.

Private test source:
`~/Development/SayStone-Acceptance/20261013-e5c8b7b`.
The directory name retains the initial staging revision; its source is the
tested `8d98a43` revision above.

Generated DerivedData, package cache and compiler temporary files are on
`/Volumes/ForgeData/SayStone-Acceptance/20261013-e5c8b7b`.
Only this task's generated directory was moved there. Personal files were not
deleted to make space. Package pins did not drift during the build.

Direct SSH certificate signing returned `errSecInternalComponent`. The same
certificate signed successfully from the logged-in GUI session. That GUI build
then encountered macOS's removable-volume access restriction. The supported
CI compilation flags produced native test products on ForgeData; these were
copied to private internal storage and signed from the GUI session. The existing
CTranscribe repair helper normalized the generated framework before strict
verification. No broader disk access or signing-key permissions were changed.

Signed runtime products:
`~/Development/SayStone-Acceptance/20261013-runtime/DerivedData/Build/Products`.
Raw private logs and xcresults:
`~/Development/SayStone-Acceptance/20261013-results`.
The authored speech helper was corrected for macOS Bash 3.2 and validated with
both the system shell and the Homebrew shell before the passing native run.

## Resume prerequisites

1. Unlock the existing Mini desktop. Screen Sharing was already running. A
   loopback-only SSH tunnel at `vnc://127.0.0.1:15900` was verified and opened on
   the MacBook to let the user authenticate directly in Screen Sharing. The
   tunnel is temporary; verify it or recreate it before reuse.
2. Allow native debugger/automation authorization. The installed
   `DevToolsSecurity(8)` manual describes `sudo /usr/sbin/DevToolsSecurity -enable`
   as allowing admin/developer-group members to use Apple debugger tools without
   another administrator-password prompt. No authorization policy was changed
   by the agent. A disabled status and locked desktop are observations; the
   timeout does not isolate their individual causal contributions.
3. Confirm the desktop is ready for about 15 minutes before rerunning only the
   four UI scenarios. Avoid launching test hosts while the user is entering
   authentication credentials. No rebuild is required for the unchanged tested
   app code; verify both signatures and the exact runtime paths first.
4. Connect a microphone for authored live capture/routing. Then complete hotkey,
   cross-app paste, cancellation/recovery and real Shortcuts checks.
5. Resume the deferred phone/profile stage only after its device, narrow
   credentials and profile-authority prerequisites are resolved as described in
   [CROSS-DEVICE-ACCEPTANCE.md](CROSS-DEVICE-ACCEPTANCE.md).

The four UI scenarios remain synthetic paste denial, literal snippet
save/edit/relaunch persistence, workflow transform/copy/persistence, and local
shortcut event capture/conflict. A passing build or unit result does not accept
any of these UI scenarios.
