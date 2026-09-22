# SayStone shared speech continuation pointer

The canonical cross-repository handoff is maintained in The Forge repository:

- Local: `/Users/colsenmangeris/oikonomos/docs/custom/handoffs/2026-09-22-saystone-shared-speech.md`
- GitHub: `https://github.com/colsenmangeris/oikonomos/blob/custom/main/docs/custom/handoffs/2026-09-22-saystone-shared-speech.md`

Read that document before continuing the MacBook/Mac Mini/iPhone work. It contains the full plan, decisions, implementation map, revisions, live deployment state, acceptance matrix, known failures, credential boundary, exact next steps, and definition of done.

SayStone source authority for this project:

- worktree: `/Users/colsenmangeris/FluidVoice-worktrees/shared-speech`
- branch: `feat/shared-speech-server`
- implementation revision: `062deae4ac07ea6f802b3b72156916a291429b7d` (the branch `HEAD` also includes this documentation pointer)
- installed build on both Macs: `1.6.10 (22)`
- bundle ID: `com.FluidApp.app.debug`
- local speech endpoint: `127.0.0.1:47733`

At the time of this pointer, both Macs report the same ready Parakeet v2 model digest, pipeline revision, profile schema, runtime commit, and SayStone build. The current blocking fact is that MacBook profile sync is enabled but receives `401 auth_invalid`; no server authority file or local sync cache exists, and Mini sync remains disabled. Do not claim shared-profile acceptance until fresh speech-scoped credentials are securely imported and bidirectional convergence is proven.

The installed Forge iPhone Preview has a later successful `0.0.80` install/launch receipt, but no successful physical-phone SayStone dictation has been recorded. Keep legacy NeMo STT available until Tailscale dictation, Forge Connect fallback, cancellation, retry/idempotency, restart, concurrency, and profile tests pass. Leave Qwen TTS untouched.
