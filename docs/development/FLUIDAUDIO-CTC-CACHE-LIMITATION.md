# FluidAudio vocabulary tokenizer cache limitation

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
