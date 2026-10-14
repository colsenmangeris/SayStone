# FluidAudio vocabulary tokenizer cache limitation

## October 13 fix

The bounded SDK change is published at
[`bce007d1c1b559f2f224bb1369bd1fc7c95fbc7a`](https://github.com/colsenmangeris/FluidAudio/commit/bce007d1c1b559f2f224bb1369bd1fc7c95fbc7a).
Xcode's package reference, Package.resolved, and the inherited Package.swift
now select that exact revision. SayStone passes the same selected CTC directory
used to load its vocabulary tokenizer and models into the boosted manager.
Public builds select their existing directory; Development selects its private
directory. Missing private assets still propagate into the existing base-ASR
fallback, without borrowing tokenizer assets from the ordinary cache.

Two opt-in native SDK tests passed using separately downloaded real CTC 110M
models and tokenizer assets in private temporary storage, with zero failures or
skips. They validate explicit-directory loading and missing-file errors; they
do not establish speech inference or recognition quality. The earlier
placeholder-model checks were preliminary and are superseded by this receipt.
See [dependency change and validation](dependency-patches/README.md).
The integrated native test products compiled on the Mini, and the final app and
UI runner pass strict deep verification with its Development certificate.
52 native units and authored Whisper acceptance pass; UI and boosted speech
inference acceptance remain separate. See
[Mac Mini acceptance](MAC-MINI-ACCEPTANCE-2026-10-13.md).
The original finding below is retained as provenance.

## Original finding

Source-reviewed on 2026-10-11 against pinned FluidAudio revision
`3fd63887eef1dc25edea8263ce4b44aa854d898b`.

SayStone selects a private Development cache when downloading TDT and CTC
models. The pinned dependency's `AsrManager.configureVocabularyBoosting`,
however, ignores the supplied CTC models' download location and constructs
`CtcModels.defaultCacheDirectory(for:)` for its tokenizer. That resolves to
the ordinary macOS Application Support model cache.

The dependency reads `tokenizer.json` and `tokenizer_config.json` from this
location. Its local tokenizer loader does not download or write those files.
These are model assets, not the daily app's settings, history, custom dictionary
or credentials. If they are absent, boosting initialization throws and
SayStone falls back to base recognition. Consequently, fully private-cache
vocabulary boosting is **not accepted** yet. No daily cache contents were
inspected to determine whether those files exist.

The base-recognition authored WAV acceptance explicitly disables boosting,
pronunciation matching and dictionary replacements in a fresh synthetic test
preferences suite. It does not establish boosted recognition.

## Bounded follow-up

Add an optional `ctcModelDirectory: URL? = nil` argument to the dependency's
public `configureVocabularyBoosting` method, using the supplied location before
falling back to its existing default. Pass SayStone's private CTC directory
when configuring the boosted manager. Public callers retain current behavior.

Review and pin the resulting dependency revision; test with an authored
vocabulary and empty synthetic public cache, then verify local fallback.
No vendored checkout, package pin, public cache, symlink or installed service
was changed as a workaround during this run.

Source pointers in the generated, pinned package checkout:

- `DerivedData/SourcePackages/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/AsrManager.swift`: `configureVocabularyBoosting`.
- `DerivedData/SourcePackages/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/SlidingWindow/CustomVocabulary/WordSpotting/CtcTokenizer.swift`: `load(from:)` and `HFTokenizer.init(modelFolder:)`.
- `DerivedData/SourcePackages/checkouts/swift-transformers/Sources/Tokenizers/Tokenizer.swift`: `AutoTokenizer.from(modelFolder:)`.
- `DerivedData/SourcePackages/checkouts/swift-transformers/Sources/Hub/Hub.swift`: local `loadConfig(modelFolder:)`.

The separate Flash provider bug was fixed in app code: its SDK download now
receives SayStone's selected cache root explicitly, and readiness follows the
chosen chunk variant. A network-boundary fixture catches both regressions;
it does not simulate real speech inference or a real model download.
