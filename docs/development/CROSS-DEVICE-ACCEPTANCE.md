# SayStone cross-device acceptance

Read-only readiness refresh: **2026-10-10 America/Denver**, probes completed
around **2026-10-11T03:14Z**. This document prepares acceptance; it does not
authorize replacing daily apps, enabling profile sync, minting/importing
credentials, changing Mini services, removing rollback, or releasing software.
The user has confirmed that the Mini and iPhone are available for the later
physical-device stage.

## Authority and boundaries

Read the canonical [2026-09-22 handoff](/Users/colsenmangeris/oikonomos/docs/custom/handoffs/2026-09-22-saystone-shared-speech.md),
[locked architecture](/Users/colsenmangeris/oikonomos/docs/custom/SAYSTONE_SHARED_SPEECH_DESIGN.md),
[0.0.77 source/release receipt](/Users/colsenmangeris/oikonomos/docs/custom/SAYSTONE_SHARED_SPEECH_RELEASE_0077.md),
and [phone behavior](/Users/colsenmangeris/oikonomos/docs/user/saystone-dictation.md).
The [SayStone continuation pointer](../custom/HANDOFF-2026-09-22-SHARED-SPEECH.md)
still includes old paths and September deployment state. The shared-speech
worktree is now `/Users/colsenmangeris/SayStone-worktrees/shared-speech`,
branch `feat/shared-speech-server`, HEAD
`3b618750bbe592f7b942ee409472981ba9d48ce2`.

The local Forge checkout currently reports branch `wt/grid-into-forge`, HEAD
`839ae71692fc64f11911da8014da63e1bb878a7d`; it is another owner's lane and is
not proof of the installed Mini release's source revision. Do not edit that
checkout or use it to mint credentials/deploy until its owning lane and the
installed release's supported auth workflow have been reconciled.

Keep daily MacBook dictation local and usable offline. Native inference stays
on the Macs; Akmon does not run SayStone. Tailscale is the phone's primary route,
Forge Connect the fallback to the same authenticated Mini endpoint. Keep NeMo
STT on `8781` and Qwen TTS on `8782` through acceptance. Neither is changed by
the utility implementation in this development checkout.

The new `SayStone Development` identity/storage is separate from the existing
daily `com.FluidApp.app.debug` identity. Do not seed the live shared profile with
an empty Development profile or copy daily vocabulary/pronunciation data into
development for a demo. Choose the intended profile authority and obtain the
task-specific activation authorization before the live profile stage.

## Confirmed current state

Only public deployment metadata, health responses, signing assessments,
listening ports, and existence metadata for the three known profile paths were
inspected. No credentials, clipboard content, dictation history, profile
payloads, SQLite receipts, or audio were read. No processes were started,
stopped, installed, updated or reconfigured.

| Surface | Confirmed on this refresh | Acceptance meaning |
| --- | --- | --- |
| MacBook daily SayStone | `127.0.0.1:47733/v1/health`: status `ok`, engine readiness `ready`, SayStone `1.6.10 (22)` | Existing daily engine is ready; this is not a new dictation or profile-convergence receipt. |
| Mini host | Existing noninteractive SSH alias `mini` works; macOS `26.6.2`; Mini Tailscale peer is online | Host is reachable. No service mutation was needed. |
| Mini SayStone | Installed daily bundle `com.FluidApp.app.debug`, version `1.6.10`, build `22`; strict deep signature verification passes; loopback health `ready` | Matches MacBook engine identity below. |
| Mini Forge | Installed bundle `com.oikonomia.theforge`, version `0.0.91`; local `/api/health` is `ready`; strict deep signature verification passes | Historical `0.0.80` runtime state is superseded. Exact installed release source SHA still needs a release receipt. |
| Mini Forge signing | Developer ID Application signature present; Gatekeeper rejects with `source=Unnotarized Developer ID` | September's ad-hoc-signing diagnosis is superseded; notarization/Gatekeeper acceptance is still pending. |
| Narrow profile auth | Unauthenticated `GET http://127.0.0.1:3774/api/speech/profile` returns `401` | Expected rejection proves the auth gate is mounted. It does not prove current saved credentials are invalid or valid. |
| Tailscale Forge route | `https://colsens-mac-mini.tail306318.ts.net/api/health` returns `200`, `ready` | Primary private route reaches the current Forge backend. Authenticated phone speech remains untested. |
| Tailscale Serve | Root route maps to `3774`; `/speech/stt` to `8781`; `/speech/tts` to `8782`; existing `8443` root maps to `4318` | Preserve all handlers. Do not reset shared Serve configuration. |
| Rollback services | NeMo STT listens on `127.0.0.1:8781`; Qwen TTS on `127.0.0.1:8782` | Rollback and TTS remain available; no live utterance/TTS request was sent. |
| SayStone remote boundary | Mini listener reports wildcard `*:47733`; a MacBook-to-Mini Tailscale `/v1/health` request timed out; server code rejects non-loopback connection endpoints | Listening-address metadata alone is not evidence that the broad LocalAPI is exposed. Retest remote rejection during acceptance. |
| Profile storage | Known MacBook cache, Mini cache, and Mini authority file are absent | No durable seed or convergence is demonstrated. Current saved token/toggle states were deliberately not inspected. |
| Physical iPhone | Mini CoreDevice lists a paired physical iPhone 16 Pro Max as `available`; iOS Tailscale peer is online | Device is available for the physical stage; reachability is not dictation acceptance. |
| iPhone Forge Preview | A bundle-filtered CoreDevice metadata query confirms `com.oikonomia.theforge.preview`, version `0.0.80`, build `20260922.002843` is installed | Confirms current Preview matches the historical install receipt. It was not launched and no recording was made. A separate Production-bundle metadata query timed out; Production state is unknown. |

The three absent known paths are:

- MacBook and Mini: `~/Library/Application Support/FluidVoice/saystone-speech-profile-sync-v2.json`.
- Mini authority: `~/.oikonomia/theforge/userdata/saystone-speech-profile.json`.

Both running SayStone health responses agree on:

| Field | Value |
| --- | --- |
| `engineId` | `saystone-parakeet` |
| `modelKey` | `parakeet-v2` |
| `modelRevision` | `fluidaudio-3fd63887eef1-tree-15d927819691` |
| `modelSha256` | `15d927819691e1528045b0b1d3a72f0f87ea1930ddbcf0a802adee24cae4eaf1` |
| `pipelineRevision` | `saystone-shared-pipeline-v1` |
| `profileSchemaRevision` | `2` |
| `runtimeCommit` | `062deae4ac07ea6f802b3b72156916a291429b7d` |
| `saystoneBuild` | `1.6.10 (22)` |

This verifies deployed engine parity, not shared profile state or identical
recognition for untested audio.

## Historical evidence and current unknowns

The last committed phone Preview receipt in the canonical checkout is
[`0.0.80-20260922.002843-99d3365b422f.json`](/Users/colsenmangeris/oikonomos/docs/custom/mobile-release-receipts/preview/0.0.80-20260922.002843-99d3365b422f.json):
Preview bundle `com.oikonomia.theforge.preview`, source
`99d3365b422fbf5844ae9521c0afe7074a40affe`, installed and launched successfully.
Its bundle/version/build now also match a fresh filtered CoreDevice metadata
check. This establishes current installation metadata, not successful SayStone
dictation or execution. Reconfirm the exact installed source receipt before the
next acceptance recording.

The September handoff recorded MacBook `401 auth_invalid`, MacBook sync enabled,
Mini sync disabled, and no profile/terminal receipts. Those token/toggle/receipt
details were **not** rechecked here. Do not describe an anonymous `401` as a
reproduction of saved-token failure. No fresh authenticated profile request,
speech session, receipt replay, pronunciation transfer or phone utterance has
been run during this readiness refresh.

## Required inputs for the next authorized stage

Before performing activation, assemble the following concrete inputs:

1. The supported auth/bootstrap procedure for the current installed Mini Forge
   release, its exact source SHA, operator identity and target Mini environment.
2. Separate narrowly scoped `speech:operate` credentials for the intended MacBook
   and Mini clients, including agreed lifetime/revocation. Never print token
   strings or pass them in shell command arguments, URLs, defaults or receipts.
3. A private `0600` bootstrap file or equivalent process-owned secret channel.
   The existing importer consumes
   `FluidVoice/saystone-profile-sync-token.import` under the selected app's
   application-support directory, stores Keychain key `saystone-profile-sync`,
   and removes the bootstrap file. Development uses its separate support root
   and Keychain service; daily app credentials are not interchangeable.
4. The chosen initial portable profile and authorization to seed the Mini
   authority from it. Seed MacBook first; leave Mini sync off until that write
   succeeds. Do not use a development profile to overwrite a daily profile.
5. The physical iPhone near the Mini, unlocked/awake, with Tailscale connected,
   the appropriate Forge Preview installed, and an authenticated Mini environment.
6. A coordinated window for forced route/process failures and concurrent use.
   Restarting Forge/SayStone or changing routes is a separate authorized action,
   not part of these read-only checks.

Token bootstrap, shared-speech activation and live retained-event/profile
processing remain pending. Availability of the phone authorizes planning and
metadata inspection; it is not a production release or service-removal approval.

## Acceptance sequence and receipts

Use authored speech/text fixtures. Each row needs a concrete receipt before it
is marked accepted. Do not record private transcript text, audio, embeddings,
tokens or unredacted query strings in repository artifacts.

| Stage | Exercise | Required receipt | Current status |
| --- | --- | --- | --- |
| Authentication | Reject no-token and wrong-scope requests; accept the intended fresh speech-scoped clients | HTTP outcomes, scope names, client/environment identifiers and timestamp; no credential values | Anonymous rejection confirmed; authenticated/scope acceptance pending |
| Profile seed | Authorized MacBook profile writes to Mini authority before Mini sync is enabled | Authority revision, entry-kind counts, file mode `0600`, MacBook cache revision | Pending |
| Profile convergence | Enable Mini after seed; add one reversible authored word/replacement on each Mac; delete it and verify tombstone/no resurrection | Both cache revisions, authored fixture IDs, add/delete outcomes, conflict outcome | Pending |
| Pronunciation compatibility | Transfer an explicitly authorized compatible entry; test mismatched model key/hidden size quarantine | Engine/model compatibility metadata and quarantine/re-enroll result; no vectors/audio | Pending |
| Mac offline behavior | Disconnect profile route and dictate an authored fixture locally | Selected local provider, final/raw fallback, visible processing, no cloud use | Historical tested path accepted; fresh integrated receipt pending |
| iPhone primary route | Select SayStone in Preview, run connection test, then short phrase and paragraph with number/name/identifier/correction | Phone bundle/version/source receipt, request ID, route, engine identity, profile revision, finalization and single insertion outcome | Pending |
| Cancellation | Cancel before commit and during processing; disregard late final | Terminal cancellation outcome and no insertion, including after reconnect | Pending |
| Route fallback | Force primary-route failure during a reviewed test window | Same request ID over Forge Connect, final inserted once, route indication | Pending |
| Both routes unavailable | Exercise visible failure/on-device choice and retry/discard | Clear failure state, bounded retained buffer and documented cleanup | Pending |
| Retained-audio retry | Cause recoverable processing/route failure, recover, retry same request ID | Terminal receipt ID, inference/replay result, no duplicate insertion, buffer deletion after success | Pending |
| Restart | Restart Forge after commit; restart SayStone during another session | Durable receipt replay or recoverable error, retained retry, no late duplicate | Pending; coordinated authorization required |
| Concurrent operation | MacBook local, Mini desktop, phone dictation and Qwen TTS in parallel | Distinct request IDs, correct session output, bounded latency, no cross-session text | Pending |
| Bounds/lifecycle | Two-minute/3,840,000-byte PCM boundary, network loss, composer edits while finalizing, background/foreground | Explicit bounded outcome, preserved composer edits, no silent loss | Pending |
| Broad API boundary | Verify remote full LocalAPI rejection while narrow authenticated Forge routes work | Remote rejection and authenticated narrow-route outcomes | Remote health timed out; complete boundary receipt pending |
| Release signing | Stage supported signed/notarized Mini Forge release after exact-SHA review | Strict signature, Developer ID/team, notarization/stapling, Gatekeeper accepted, post-swap health | Pending; current Gatekeeper rejection confirmed |
| Rollback/cutover | Prove phone return to still-running NeMo/on-device route before deciding cutover | Exact installed revisions, rollback result/window, operator decision | Pending; NeMo remains |

Protocol constants remain final-only 16 kHz mono signed PCM16, two-minute maximum,
client `requestId` idempotency, terminal cancellation, server memory-only audio,
durable terminal receipts, and Tailscale-first/Forge-Connect fallback. Profile
sync transfers portable words/aliases/replacements/preferences and compatible
pronunciation embeddings; microphone/shortcut/endpoint/credential settings stay
device-local.

Suggested receipt fields:

```json
{
  "fixtureId": "authored-cross-device-001",
  "startedAt": "<UTC timestamp>",
  "phoneBundleId": "com.oikonomia.theforge.preview",
  "phoneVersion": "<verified version/build>",
  "forgeSourceCommit": "<exact deployed SHA>",
  "saystoneRuntimeCommit": "062deae4ac07ea6f802b3b72156916a291429b7d",
  "requestId": "<nonsecret request UUID>",
  "route": "tailscale",
  "profileRevision": null,
  "outcome": "pending",
  "insertions": 0,
  "audioPersistedByServer": false,
  "notes": "<sanitized visible outcome; no transcript or secrets>"
}
```

Receipts should be stored with the owning Forge acceptance lane and linked here.
This readiness document is not itself a receipt for authenticated speech.

## Cutover and release gates

After the whole phone/profile matrix passes, the operator can decide whether to
make SayStone the phone default. Prove rollback while NeMo still runs, record
the exact release revisions and agreed rollback window, and obtain explicit
task-specific service-removal authorization before changing its LaunchAgent or
Serve handler. Qwen TTS is always outside the STT removal scope.

Preview acceptance does not authorize Production phone installation. The locked
handoff requires fresh explicit approval naming the exact full pushed SHA before
the supported Production command. Neither daily SayStone replacement, Mini
desktop release swap, Production phone installation, nor NeMo removal occurred
in this development task.
