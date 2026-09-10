# SayStone

## Scope
Preserve existing appearance, providers, model choices and logos. Build a permissively licensed enhancement layer. Keep Parakeet as the quality reference. Do not modify Forge or interrupt ChatGPT work during this stage.

## Baseline and reliability
Baseline commit: 42e33e68ec473129ad090521e56c22c912a16db3. Personal origin and upstream/main configured. The unchanged signed public baseline launched and loaded Parakeet v2. It has since been replaced by the patched personal build. Microphone and Accessibility grants are verified in the installed app; live reliability acceptance remains pending.

Branch fix/audio-start-recovery bounds the configured hardware startup wait to three seconds. Cancel wakes the waiter immediately. The underlying operation remains owned until its existing cancellation/serialized cleanup completes. New starts are rejected while it is recovering. Failed deadlines do not blacklist the microphone. This is a containment/recovery fix for the observed AudioDeviceStart stall, not a repair of macOS Core Audio or proof that ChatGPT causes it. No other process is terminated by the fix.

Regression tests: xcrun swiftc Sources/Fluid/Services/AudioStartupDeadline.swift Tests/AudioStartupDeadlineTests.swift -o /tmp/fluid-start-deadline-tests && /tmp/fluid-start-deadline-tests
Build: ./build.sh public
Generated CTranscribe framework requires layout repair and re-signing with scripts/local/repair-framework-bundle.py APP --identity ID. Do not commit signing identities, model weights, or private transcripts.

Before daily use: test normal startup, hold-release cancellation while connecting, three-second failed start, immediate retry rejection during recovery, late completion with no pasted text, and successful recording after recovery. Verify installed build under actual desktop conditions. Review upstream updater behavior before replacing the user's release.

## Enhancement comparison
Both candidate weights downloaded locally; BitVoice Qwen3-0.6B imported into Ollama as fluidvoice-bitvoice-eval; SpeakoFlow mini Q8_0 via Hugging Face. Ollama local endpoint only.
Authored 12-case smoke suite and outputs under evaluation/. It is NOT an audio/Parakeet accuracy benchmark or representative quality study. Includes a no-op reference, exact-match convenience score and human-inspectable outputs. SpeakoFlow's separate rules layer is not included. First request includes model loading, so latency is not a warm benchmark. Both models preserve several already-correct texts, names, numbers and code identifiers, but both fail the Thursday→Friday correction case. Do not select a default enhancement model on these results.
Next: compare real raw Parakeet transcripts against both cleanup models and independently reviewed desired text, including long dictation and explicit corrections. Preserve raw output and permit enhancement bypass.

## Additional transcription models
Qwen exists in settings but is disabled; ASRService has a comment indicating support removal and a legacy fallback to Parakeet v3. Do NOT enable the preview flag and call it Qwen support. Qualify a real Qwen3-ASR implementation and model identity first.
MAI-Transcribe-2 requires a hosted provider adapter and configured credentials; no credential or paid request has been made. Microsoft documents REST multipart audio and enhancedMode.model=MAI-Transcribe-2. Preserve existing choices when adding it.

## Cross-device requirements, not implementation decisions
User has a working Forge iPhone WebSocket to the Mini, wants better speech recognition, shared preferences/vocabulary, and possibly a keyboard across apps. Do not replace the current connection yet. Evaluate local Mini, cloud and device execution against measured latency, availability, privacy, battery and cost. Design preferences separately from inference transport. Inspect current Forge implementation and iOS extension constraints before committing to a keyboard architecture. No Forge files changed.

## SayStone branding (2026-09-09)
Repository: https://github.com/colsenmangeris/SayStone; upstream remote retained. Tagline: What you say becomes something you can build on. Installed signed build: ~/Applications/SayStone.app. App window, menu name and onboarding branding updated while preserving the existing design, provider logos, storage keys and com.FluidApp.app.debug identity. Build and strict deep signature verification passed. Installed UI confirms SayStone title, tagline, microphone and Accessibility grants. Previous installed FluidVoice Debug.app moved to Trash; generated build artifacts and Trash can still appear in Spotlight.

## Recording compatibility candidate (2026-09-09 evening)
The deadline-only build failed live acceptance: it avoided a stuck UI but did not restore recording during direct AudioDeviceStart stalls. Reliability remains the priority; enhancement/provider/device work is paused.

The installed candidate defaults to AVAudioEngine capture, with direct capture retained under the diagnostic SayStoneDirectAudioCaptureEnabled defaults key. The default-microphone binding now preserves AVAudioEngine's managed duplex route. Unified logs showed the old binding replaced an aggregate with the input-only built-in microphone, rejected as unusable for simultaneous input/output (-10851), leaving a zero-channel format.

Validation: public build, repaired framework signature, deadline regression suite and diff checks passed. Two installed-app microphone sessions received PCM and stopped through the playground UI. The first session retried once following an engine configuration change; the second reached first PCM on its first attempt (about 183 ms from backend selection). ChatGPT stayed running. User reproduction inside ChatGPT is still pending, so this is not accepted as a final reliability fix. Non-default microphone selection, hotplug and Bluetooth remain unqualified for this compatibility path; the retained AVAudioEngine startup is synchronous and the deadline does not guarantee responsiveness while it blocks the main actor.

## User acceptance and enhancement review (2026-09-09)
User reports repeated recording in ChatGPT now works without issues and authorizes proceeding in order. This accepts the tested built-in/default-microphone path; other route caveats above still apply.

Completed local review of 10 unique history transcripts of at least 20 characters (from 20 entries at snapshot time), unchanged versus BitVoice Qwen3-0.6B and SpeakoFlow mini Q8_0. Repeated the SpeakoFlow comparison with upstream MIT reference rules at baffdf46fcd991f3789d08b2f1d8067f92f29b01: the configured English rules did not change these already formatted inputs. No vocabulary or emoji expansion was configured. Private texts/results remain outside the repository in the troubleshooting directory; reusable read-only runners are in evaluation/.

BitVoice omitted a complete final question from one longer input and rewrote another passage. SpeakoFlow preserved all eight non-repetition inputs and collapsed repetition in two recording checks. Neither repaired the observed recognition errors in project names/phrasing. Decision: keep unchanged text as default; SpeakoFlow is the more conservative candidate for optional cleanup, but this small convenience sample supplies no audio ground truth, WER, or representative accuracy claim. The existing 12-case authored suite also exposed unsupported corrections. No automatic enhancement setting changed.

Sources: https://huggingface.co/dhanr4j/bitvoice-dictation (selected Qwen3 file listed Apache-2.0; repository contains other licenses), https://huggingface.co/SpeakoFlow/speakoflow-mini (Apache-2.0), https://github.com/AbhishekBarali/dictation-cleanup-rules (MIT). Preserve applicable notices if shipping these assets/code.
