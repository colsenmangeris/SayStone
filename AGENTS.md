# SayStone: agent instructions

SayStone is Colsen's personal fork of FluidVoice, a macOS voice-to-text app written in Swift (Xcode project `Fluid.xcodeproj`, dependencies through Swift Package Manager). Remotes: `origin` is `colsenmangeris/SayStone`; `upstream` is `altic-dev/FluidVoice`. Project instructions live in this file; do not create `CLAUDE.md`.

## Branches
- `main` follows upstream FluidVoice. Colsen's own changes live on branches (for example `fix/audio-start-recovery`).
- Fork status, decisions and test notes are in `docs/custom/` on `fix/audio-start-recovery` (start with `docs/custom/STATUS.md` there). Read it before changing recording, providers or branding.
- Bring in upstream changes by hand. `CONTRIBUTING.md` and the README's pull-request rules are upstream's rules for PRs to `altic-dev/FluidVoice`; do not open PRs there unless Colsen asks.

## Where to build
- macOS only. Linux hosts can edit code but cannot build or run it.
- From a Linux host, build on the Mac mini with the `mac-build` script (source `~/grid/fleet/mac-build`): `mac-build --project Fluid.xcodeproj --scheme Fluid --platform macos`. Add `--test` to run tests. Run `mac-build --done` when finished.

## Build and test (on a Mac)
```sh
./build.sh                 # signed Debug build (default profile: public)
./build.sh unsigned        # unsigned fallback when no signing identity exists
xcodebuild test -project Fluid.xcodeproj -scheme Fluid -destination 'platform=macOS'
scripts/format-and-lint.sh # SwiftFormat and SwiftLint
```
- The signed build is written to `DerivedData/Build/Products/Debug/`. Keep launching that product after each rebuild so macOS keeps its Accessibility grant.
- With certificates for several teams, pick one without changing the project: `FLUIDVOICE_DEVELOPMENT_TEAM=<team id> ./build.sh`.
- `scripts/test_*.sh` hold narrower checks for single areas.

## Never commit
- Personal team IDs, signing identities or API keys (`scripts/check-team-id.sh` can run as a pre-commit hook).
- Model weights, recordings or private transcripts.
