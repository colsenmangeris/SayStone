# CTC tokenizer directory candidate

Prepared October 13, 2026 against FluidAudio
`3fd63887eef1dc25edea8263ce4b44aa854d898b` and SayStone
`e5c8b7b197447b262b61bae6b260a9ad37af2da3`.

The user authorized SDK fork publication and SayStone pinning on October 13.
The SDK change is published to
[`colsenmangeris/FluidAudio` at `bce007d1c1b559f2f224bb1369bd1fc7c95fbc7a`](https://github.com/colsenmangeris/FluidAudio/commit/bce007d1c1b559f2f224bb1369bd1fc7c95fbc7a),
and the caller changes are applied in the feature checkout. Xcode and the
inherited package manifest select that immutable revision. The patch files
preserve the reviewed delta from the original revisions.

## Changes

[fluidaudio-ctc-model-directory.patch](fluidaudio-ctc-model-directory.patch)
adds `ctcModelDirectory: URL? = nil` after the existing optional configuration
argument. The rescorer receives that directory when supplied. Omitting it keeps
the variant's existing default. A failure loading the requested directory is
propagated rather than retried against the ordinary cache.

[saystone-ctc-model-directory.patch](saystone-ctc-model-directory.patch) carries
the directory already used for the downloaded CTC models and vocabulary
tokenizer through the vocabulary bundle into the final manager. It preserves
the existing cancellation checks and base-recognition fallback. Apply this
caller patch only after pinning a dependency containing the SDK change.

Source reviewed: [pinned AsrManager](https://github.com/altic-dev/FluidAudio/blob/3fd63887eef1dc25edea8263ce4b44aa854d898b/Sources/FluidAudio/ASR/Parakeet/AsrManager.swift),
[pinned VocabularyRescorer](https://github.com/altic-dev/FluidAudio/blob/3fd63887eef1dc25edea8263ce4b44aa854d898b/Sources/FluidAudio/ASR/Parakeet/SlidingWindow/CustomVocabulary/Rescorer/VocabularyRescorer.swift),
and [pinned CtcTokenizer](https://github.com/altic-dev/FluidAudio/blob/3fd63887eef1dc25edea8263ce4b44aa854d898b/Sources/FluidAudio/ASR/Parakeet/SlidingWindow/CustomVocabulary/WordSpotting/CtcTokenizer.swift).

## Validation

The complete patched SDK compiled locally with the application's exact eight
transitive tokenizer dependency revisions. The temporary package manifest
selected only the added `VocabularyCacheIsolationTests` file, preserving all SDK
production sources and avoiding unrelated inherited test suites. SwiftPM used
`--force-resolved-versions`. Two native XCTest tests passed, zero failures/skips:

- The CTC 110M model loads and encodes tokenizer assets from an explicit
  private temporary directory, preserves the supplied rescorer configuration,
  and enables vocabulary boosting without CoreML prediction or test-time downloads.
- A missing private tokenizer throws an error naming that directory. It does
  not fall back to another cache. Disabling the failed manager clears boosting.

The legacy call shape also compiled without executing its ordinary-cache read.
The final tests use separately provisioned real CTC 110M models and tokenizers,
fresh 0700 temporary directories, and the authored term SayStone. The earlier
placeholder-model tests are superseded and are not included in the published
SDK change. The tests do not establish speech inference, recognition quality,
the caller's native app build, or real-device acceptance.
No daily cache contents, settings, history, clipboard or credentials were read.

Local SDK test log:
`/tmp/saystone-ctc-review-20261013/sdk-real-model-tests.log`.
Model provenance is in `/tmp/saystone-ctc-real-models-20261013/provenance.json`:
Hugging Face model revision `accdafd8cf8a2ff1cabe3c11e54416b405d409aa`, with
each downloaded artifact's size and SHA-256 recorded. The published tests require
`FLUIDAUDIO_CTC_TEST_MODELS_DIRECTORY`; absent provisioned assets produce a skip.
The caller patch passed `git apply --check` against the feature checkout.

## Integration order

1. Publish the bounded SDK change to an authorized fork or upstream revision.
   The repository's AGENTS.md requires task-specific authorization for publication.
2. Pin Xcode's FluidAudio package reference and Package.resolved to that exact
   immutable revision. Reconcile the inherited Package.swift reference as well.
3. Apply the caller patch and rebuild the signed Development app. The framework
   repair and strict signature verification remain required.
4. Run the cache tests, safe fixtures, and authored boosted-recognition acceptance
   on the isolated test Mac. Missing-model/download guards and base fallback must
   remain visible; a passing cache test is not an inference receipt.

Do not silently patch Xcode's generated dependency checkout, link the ordinary
cache into Development storage, or copy daily tokenizer/model data for this test.
