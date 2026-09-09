# Personal FluidVoice fork

## Scope
Preserve existing appearance, providers, model choices and logos. Build a permissively licensed enhancement layer. Keep Parakeet as the quality reference. Do not modify Forge or interrupt ChatGPT work during this stage.

## Baseline and reliability
Baseline commit: 42e33e68ec473129ad090521e56c22c912a16db3. Personal origin and upstream/main configured. Signed public baseline at ~/Applications/FluidVoice Debug.app; source unchanged. It launches and loads Parakeet v2. Microphone and Accessibility grants, live transcription and insertion acceptance are pending user permission.

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
