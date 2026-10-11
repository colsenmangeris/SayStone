# SayStone development

SayStone is an existing native macOS app, built with SwiftUI, AppKit,
AVFoundation and native speech/model dependencies. Extend the app in place.

## Workspace and builds

- Read `docs/development/START-HERE.md` before changing the build or environment.
- The app build is `SayStone.xcodeproj`, shared scheme `SayStone`, destination
  `My Mac`. Run `./build.sh` for the signed public Debug build. The standalone
  Package.swift is inherited and is not the authoritative app build entrypoint.
- Inspect git status and the active branch before edits. Preserve unrelated
  changes and worktrees. Work on the feature checkout selected in T3 Code.
- Use Xcode MCP when available for diagnostics, previews and native build tools;
  shell/xcodebuild remains available when the connection is pending.
- For generated CTranscribe.framework bundles, preserve the framework repair
  helper and verify `codesign --verify --deep --strict` before packaging.

## Product constraints

- Preserve the existing visual baseline, tagline, provider choices, storage
  keys, Keychain entries and app identity unless the task explicitly changes them.
- Keep macOS 15 support; gate newer APIs. Do not migrate language mode solely
  because a newer compiler is installed.
- Preserve reliable dictation, visible processing/delivery, raw-text fallback
  and recoverable recognition failures. Reuse existing services and settings.
- Use typed, bounded workflow actions with cancellation. Keep credentials in
  Keychain and local speech/clipboard processing as the default.
- Validate UI changes against native Mac conventions and available design assets.

## Verification

Use authored text/audio and synthetic clipboard fixtures. Do not inspect private
transcripts, clipboard history or credentials merely to test a feature. Native
microphone routing, global hotkeys, permissions and cross-app paste require a
real Mac; a passing build does not establish those behaviors.

The daily app is `~/Applications/SayStone.app`. Its Debug bundle ID matches
this build, so interactive runs can share data and permissions. Establish an
isolated development identity/data location before routine interactive testing.
Installing over the daily app, enabling shared-speech services, publishing or
releasing requires task-specific authorization.
