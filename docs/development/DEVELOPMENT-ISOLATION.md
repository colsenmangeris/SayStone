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

## Remaining native acceptance

Neither the daily app nor the development app was launched for this work.
The daily installation at `~/Applications/SayStone.app` was not replaced.
No daily settings or history were inspected or copied, and no shared-speech
service was enabled. Full hosted test execution, native microphone routing,
hotkeys, development permissions, cross-app paste and cross-device behavior
remain unverified. Test those using authored audio/text and synthetic clipboard
fixtures, with the Development configuration.
