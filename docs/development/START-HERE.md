# SayStone development workspace

Use **T3 Code/Codex for coding** and **Xcode for native builds, previews,
profiling and debugging**. Xcode MCP connects these workflows. You can keep
both applications open against the same checkout; no second project or rewrite
is needed. SayStone already is a native Swift macOS application.

## Paths and repository

| Purpose | Location |
| --- | --- |
| Git repository and original recovery branch | `/Users/colsenmangeris/SayStone` |
| Current development checkout | `/Users/colsenmangeris/SayStone-worktrees/mac-workflows` |
| Development branch | `feat/mac-workflows` |
| Shared speech checkout | `/Users/colsenmangeris/SayStone-worktrees/shared-speech` |
| Personal origin | `https://github.com/colsenmangeris/SayStone.git` |
| Upstream | `https://github.com/altic-dev/FluidVoice.git` |

The FluidVoice-named local directories were moved and Git worktree references
repaired. Existing branch history is retained. The recovery checkout's existing
`docs/custom/STATUS.md` change is preserved. Historical handoffs may refer to the
old paths; use the paths above for current commands. Only `feat/mac-workflows`
has the project/scheme organization changes; the other branches retain their
own committed project versions.

## Start a T3 coding session

1. **SayStone is already registered in T3** at the current development
   checkout above. Select SayStone when starting a new thread.
2. Verify branch `feat/mac-workflows` and use the current checkout.
   This conversation began in T3's scratch folder; its working directory is not
   automatically changed by renaming the repository.
3. Read [BUILD-PROMPT.txt](BUILD-PROMPT.txt), then send it when ready to begin
   feature work. Setup has not executed the feature prompt.

Do not select the older recovery checkout for this feature build.

## Xcode

Open `SayStone.xcodeproj` from the current development checkout. Select scheme
**SayStone** and destination **My Mac**. Run, Test, Analyze and Profile use the
isolated **Development** configuration, producing **SayStone Development.app**.
Archive retains the public Release configuration. The authoritative app build
is Xcode, not `swift run`.

```sh
cd /Users/colsenmangeris/SayStone-worktrees/mac-workflows
./build.sh development
```

First-time package approval: Xcode can ask to trust MLX's `CudaBuild` plugin.
The setup run reviewed the exact pinned plugin source: its macOS branch returns
no commands. For that reviewed dependency set, this existing per-build switch
allows the CLI build to proceed:

```sh
SAYSTONE_REVIEWED_PACKAGE_PLUGINS=1 ./build.sh development
```

This passes Xcode's package-validation skip flag for this invocation; it does
not create persistent global trust. Re-review package plugins when pins change,
or approve the specific plugin through Xcode's normal interface.

Development output:
`DerivedData/Build/Products/Development/SayStone Development.app`.
`./build.sh` and `./build.sh public` retain the public Debug build at
`DerivedData/Build/Products/Debug/SayStone.app`; do not launch that build for
routine development because it shares the daily app's identity and data.
The build helper generates signed speech-engine metadata and uses an installed
Apple Development certificate. Local team details remain outside the repository.
The signed build helper repairs CTranscribe.framework and verifies the strict
deep signature automatically. For a separately generated Xcode build, the
existing helper is available:

```sh
python3 scripts/local/repair-framework-bundle.py \
  'DerivedData/Build/Products/Development/SayStone Development.app' \
  --identity '<exact installed certificate name or SHA-1>'
codesign --verify --deep --strict 'DerivedData/Build/Products/Development/SayStone Development.app'
```

A matching signing identity is necessary; use its specific certificate name
when more than one development certificate is installed. Repair only generated
build products. Do not copy over the daily installed app as part of setup.

The shared scheme includes `FluidDictationIntegrationTests`, using the
Development host and its separate data. Tests launch the host application, so
inspect their effects before running them. Compilation alone is available with
`build-for-testing`. To execute authorized tests:

```sh
xcodebuild test -project SayStone.xcodeproj -scheme SayStone \
  -configuration Development \
  -destination 'platform=macOS'
```

## Xcode MCP

This Mac already has an enabled Codex server named `xcode`, running
`xcrun mcpbridge`. Xcode Settings → Intelligence → Model Context Protocol is
set to **While Xcode is Open**. Keep the project open when connecting.

For a new Codex installation, the official configuration command is:

```sh
codex mcp add xcode -- xcrun mcpbridge
```

No duplicate server or credential was added here. Xcode requires an **Allow**
prompt for a connecting agent. A temporary setup probe initialized the bridge,
but tool enumeration waited for that approval. This existing T3 thread has no
Xcode tools in its tool catalog. Start the project thread/reconnect the Codex
session and confirm Xcode tools are available; configured does not mean connected.
Shell builds remain usable while that connection is pending.

References: [Apple Xcode agent access](https://developer.apple.com/documentation/xcode/giving-external-agents-access-to-xcode),
[Codex MCP configuration](https://developers.openai.com/codex/mcp).

## Installed environment

Inspected 2026-10-10: Apple Silicon, macOS 26.6.2; selected developer directory
`/Applications/Xcode-beta.app/Contents/Developer`; Xcode 27.0 beta 5; Apple Swift
6.4. App deployment target is macOS 15, Swift language mode is 5. Xcode's beta
version does not require changing either setting.

Git, xcodebuild, codesign, Codex, Claude, shortcuts CLI, Homebrew, ffmpeg,
ffprobe and Ollama are available. Apple Development signing is present;
Developer ID Application was not found. SwiftLint, SwiftFormat and xcbeautify
are optional and were not globally available on PATH.

For this Mac-only app, **no iOS or Android simulator is needed**. Use My Mac,
SwiftUI previews, the Xcode debugger and Instruments. Real microphone, Bluetooth,
Accessibility permissions, hotkeys and target apps are necessary for integration
acceptance. On-device model availability is separate from a successful build.

Useful tools are Xcode MCP, documentation access, Git/GitHub and native UI
inspection. Google Workspace, Slack, database and mobile-device connectors are
not prerequisites for building this app. No new plugin or paid service was added.

## Daily app boundary

`~/Applications/SayStone.app` is the existing daily app (1.6.10, build 22).
The public Debug bundle ID remains `com.FluidApp.app.debug`; launching that
build can share its preferences, storage, permissions and single-instance behavior.
Routine Xcode Run/Test actions now select the isolated Development configuration:

| Boundary | Development location or identity |
| --- | --- |
| App name | `SayStone Development` |
| Bundle ID / preferences domain | `com.architech.saystone.development` |
| App-owned data root | `~/Library/Application Support/SayStone Development` |
| History, audio, vocabulary, profile cache | `Application Support/FluidVoice/` under the development root |
| Recognition recovery / Qwen model | `Application Support/SayStone/` under the development root |
| FluidAudio models (ASR, CTC, VAD, diarizer) | `Application Support/FluidAudio/Models/` under the development root |
| Whisper, Nemotron, external CoreML caches | `Caches/` under the development root |
| Logs | `Library/Logs/Fluid/` under the development root |
| Provider / profile token Keychain service | `com.architech.saystone.development.provider-api-keys` |

Preferences use macOS's separate bundle domain in `~/Library/Preferences/`.
Storage is selected by the `SAYSTONE_DEVELOPMENT` compilation condition, so it
works when opening the generated app directly, without launch environment variables.
The app checks its development bundle identity and prepares private data folders
before initializing settings or services. Public Debug/Release paths, provider
choices, storage keys and Keychain names retain their existing behavior.

The development build starts with its own settings and history. It does not
copy the daily app's data, credentials or models. Local models are downloaded
into development storage when selected. Self-updates and rollback are blocked
for Development to preserve its identity; rebuild it through Xcode or the helper.
No daily app replacement install is part of this workflow. Recognition, cleanup,
clipboard and cross-device acceptance remain separate from compilation.

See [DEVELOPMENT-ISOLATION.md](DEVELOPMENT-ISOLATION.md) for validation evidence
and standalone fixture checks. The system boundaries follow Apple's
[preferences domains](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/UserDefaults/AboutPreferenceDomains/AboutPreferenceDomains.html)
and [generic-password Keychain attributes](https://developer.apple.com/documentation/security/ksecclassgenericpassword).

## Validation

See `SETUP-VALIDATION.txt` for the setup checks and build result.
