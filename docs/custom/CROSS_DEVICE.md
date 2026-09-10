# SayStone across devices

## Verified source inventory
Read-only inspection of `/Users/colsenmangeris/oikonomos` at `44266881bd6b94e2354b67d84bbe538fc3aa941f`. This is source evidence, not a fresh Mini or physical-iPhone deployment check. No Forge files, services or device settings changed.

- `infra/mini-speech/README.md` describes NeMo-Speech.cpp on Mini loopback port 8781, served through Tailscale HTTPS at `/speech/stt`. Its launch agent supervises the process. Qwen on port 8782 is **TTS**, not Qwen ASR.
- `infra/mini-speech/versions.env` pins the STT model to Nemotron 3.5 streaming 0.6B Q8_0, with model revision and hash.
- `apps/mobile/src/features/stt/serverDictationProvider.ts` sends PCM through a realtime WebSocket, accepts partial/final events, carries language and vocabulary hints, and bounds connection/finalization waits.
- `apps/mobile/src/features/stt/sttServerConfig.ts` stores the server credential in Expo SecureStore and keeps provider configuration separately.
- `apps/mobile/src/lib/sttPreferences.ts` defines device-local provider, endpoint, language and vocabulary preferences, including existing Forge/Oikonomos defaults.

## Proposed next implementation
Keep the working Mini WebSocket as the streaming transport. A WebSocket is appropriate for continuous PCM and partial text; replacing it with a cloud request alone does not improve personalization. Offer cloud final transcription as an explicit provider choice after measuring latency, cost and availability. Keep Apple on-device capture/recognition as the offline route where supported.

Extract the personal configuration from any single inference model. Use a versioned document containing vocabulary, explicit replacements, language choice, punctuation preferences, selected cleanup profile and per-app overrides. Keep credentials and network endpoints device-local. Preserve raw recognition separately from optional cleanup output.

A minimal first synchronization step should be explicit export/import of this non-secret profile between SayStone and Forge. Then introduce authenticated revision-based synchronization, with per-entry identifiers and tombstones so edits and deletions on two devices can be reconciled. No automatic learning from private transcript history without a separate user-facing choice.

Use a provider-neutral request/result boundary:

- Request: session ID, model ID, PCM format, language hint, profile revision and vocabulary.
- Result: session ID, sequence/revision, partial/final marker, raw text, optional cleaned text, actual model ID, timing and recoverable error code.
- Cancel must stop insertion; late output from an old session must never type into a new editor.

For a cloud route, keep long-lived Azure keys on the trusted host or device Keychain. Do not put a cloud credential into a keyboard's shared preferences. The current mobile WebSocket uses an API-key query parameter; preserve it for compatibility initially, redact URL queries in logging, and prefer short-lived connection tickets for any broader network exposure.

## Keyboard boundary
A keyboard extension is not the microphone recorder. Apple's keyboard documentation describes microphone restrictions and cases where custom keyboards are unavailable. A companion SayStone iOS app should own an explicitly started recording session; the keyboard can insert its completed text through an App Group handoff. Prototype the app-to-keyboard handoff on a physical iPhone before promising seamless dictation in every app. Secure text fields and apps that disallow third-party keyboards need a separate fallback.

Sources: [Apple keyboard configuration](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard), [Apple custom keyboard guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html).

## Acceptance before changing the working phone route
Compare the same authorized audio on current Mini Nemotron, local Parakeet/Qwen and configured MAI. Measure time to first partial, stop-to-final, errors on disconnect, and literal preservation of names, numbers and corrections. Test Wi-Fi, cellular/Tailscale, Mini unavailable, foreground/background transitions and cancellation. Then ship profile export/import in isolated Forge and SayStone changes. A passing `/ready` endpoint alone is not mobile acceptance.
