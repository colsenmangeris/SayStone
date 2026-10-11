# SayStone development isolation

Established in `feat/mac-workflows` on 2026-10-10, before launching the app.

## Identity and storage

The `SayStone` shared scheme now runs, tests, analyzes and profiles the
`Development` configuration. Its product is **SayStone Development.app**,
with bundle identifier and preferences domain
`com.architech.saystone.development`. The public Debug and Release build
configuration objects are unchanged; Archive still uses Release.

The app-owned development data root is:

```text
/Users/colsenmangeris/Library/Application Support/SayStone Development
```

The root and its `Application Support`, `Caches`, and `Library` subdirectories
were created and their permissions verified as `0700`. History, saved audio,
vocabulary, pronunciation enrollments, profile sync cache and token import,
recovery audio, local model downloads and deletion, logs, rollback storage and
analytics storage resolve under this root. macOS preferences use the separate
bundle domain under `~/Library/Preferences/`.

FluidAudio's pinned vocabulary-boosting tokenizer loader is an exception to
complete model-cache isolation: it reads `tokenizer.json` and
`tokenizer_config.json` from the SDK's ordinary CTC cache path even when the
app loads its CTC models from Development storage. Source review found no
download or write in that tokenizer loader, and missing assets fall back to
base ASR. Fully isolated vocabulary boosting is still pending; see
[FLUIDAUDIO-CTC-CACHE-LIMITATION.md](FLUIDAUDIO-CTC-CACHE-LIMITATION.md). This
review did not inspect the daily app's cache contents.

Provider credentials and speech-profile tokens use the Keychain service
`com.architech.saystone.development.provider-api-keys`. Both normal access
and the settings screen's access probe use this service. No daily credentials
were read, copied, migrated or removed. Public builds retain
`com.fluidvoice.provider-api-keys`.

`SAYSTONE_DEVELOPMENT` selects storage at compile time. No environment variable
is required when opening the generated development app. Startup rejects a
mismatched development bundle ID before settings and app services initialize.
Self-update and rollback are blocked in Development to prevent replacement by
a public app with the daily identity. Development model manifest generation
also uses only the development model directory.

## Build and verification

Build the signed isolated app:

```sh
SAYSTONE_REVIEWED_PACKAGE_PLUGINS=1 ./build.sh development
```

The package-validation switch is for the previously reviewed, unchanged pinned
package plugins; see [START-HERE.md](START-HERE.md). Build output:

```text
/Users/colsenmangeris/SayStone-worktrees/mac-workflows/DerivedData/Build/Products/Development/SayStone Development.app
```

Verified:

- Signed Development build passed; built bundle ID, display name and executable
  are development-specific. Deployment target remains macOS 15; Swift mode 5.
- `build-for-testing` passed without launching its host. The generated
  `.xctestrun` host path points to `Development/SayStone Development.app`.
- CTranscribe.framework repair was applied after both build steps. Final
  `codesign --verify --deep --strict` passed. A separate Xcode build can recopy
  the framework; use the repair instructions in START-HERE before launching it.
- Standalone development and public isolation tests passed, preserving authored
  daily-app fixtures after development history/cache deletion and recovery saves.
  The development identity guard rejected a synthetic daily-ID bundle.
- Existing history persistence tests passed: 8,400-entry migration, exact
  round-trip, recovery/retry, clear/restart and concurrent changes.
- Existing recovery tests passed: WAV encoding, clipping, private file
  permissions and latest-file replacement.
- Public Debug/Release configuration objects match their previous versions
  exactly; dependency pins are unchanged. Project, shell and diff checks passed.

Repeat the standalone isolation checks (no app host or Keychain I/O):

```sh
bash Tests/run_development_isolation_tests.sh
```

Build logs are local:
`/tmp/saystone-development-build.log` and
`/tmp/saystone-development-test-build.log`.

### Background synthetic review on 2026-10-11

The signed temporary review helper embeds a fresh UUID only in a generated copy
of the exact Development product. Invalid embedded metadata fails before normal
startup; valid metadata selects a UUID preferences suite and utility data under
the platform temporary directory. Compile-time Development and public fixtures
verify UUID/identity/namespace and foreground/background guards. Normal app
identity and ordinary Development startup are unchanged.

Native Computer Use verified the copied executable PID/path and synthetic
workspace before authored search/trim. Its focus monitor caught a desktop
activation during the text/action sequence. Review stopped and the copy was
closed and removed after verified exit; the dedicated desktop remains required
for further interaction. No general clipboard input, permissions, microphone,
Keychain or daily data were used. This copy shares ordinary Development's
permissions ID, so it is unsuitable for App Intent discovery acceptance.
See [NATIVE-UI-REVIEW.md](NATIVE-UI-REVIEW.md).

### Overnight verification on 2026-10-11

The Flash provider now passes its Development model destination explicitly to
the pinned SDK. Its previous implicit default could write to the ordinary
cache and then fail the app's private-path readiness check. Model-directory
selection now matches all three streaming chunk choices. A standalone fixture
compiles the actual provider against an SDK stub with a different public default
and verifies the explicit destination, readiness and cache clearing for each
chunk. Both pre-fix variants fail that fixture.

The actual native Whisper Tiny provider recognized the repository's authored
WAV as `Hello Fluid Voice` twice, then passed again using only the private cached
model. Those tests use synthetic preferences with pronunciation matching and
the custom dictionary explicitly disabled. The model is confined to the
acceptance-specific Development directory:

```text
/Users/colsenmangeris/Library/Application Support/SayStone Development/Application Support/AuthoredSpeechAcceptance/WhisperModels
```

Receipts: `/tmp/SayStone-Overnight-Whisper.xcresult` and
`/tmp/SayStone-Overnight-Whisper-Cached.xcresult`; one passing test and no skips
or failures in each. This proves authored-file inference and repeated final
recognition, not microphone routing or daily-use dictation. Standard Development
provider caches were not populated by copying daily models.

Parakeet v2 acceptance was explicitly skipped because less than its required
8 GB was free. No Parakeet model download started. The receipt
`/tmp/SayStone-Overnight-Parakeet-Guard.xcresult` contains one skip and zero
passes; the acceptance helper returned exit status 3.

## Remaining native acceptance

The Development app has since been launched for native utility smoke tests with
the synthetic startup documented in START-HERE.md. It uses a separate test
preferences domain, temporary utility data and named pasteboard, and skips
audio/models, Keychain, analytics, API/profile services and clipboard polling.
The daily installation at `~/Applications/SayStone.app` was not replaced or
reconfigured.
No daily settings or history were inspected or copied, and no shared-speech
service was enabled. Hosted CI execution, native microphone routing,
hotkeys, development permissions, cross-app paste and cross-device behavior
remain unverified. Test those using authored audio/text and synthetic clipboard
fixtures, with the Development configuration.

Current Mac UI acceptance is also pending. The overnight combined run passed
52 safe hosted units and three UI cases but lost the palette window; the latest
UI-only run failed all four cases while waiting for the synthetic workspace in
setup. Earlier passing UI receipts are historical and do not establish acceptance
for this revision. Foreground XCTest automation is held until an uninterrupted
test window or a dedicated test Mac is available.
