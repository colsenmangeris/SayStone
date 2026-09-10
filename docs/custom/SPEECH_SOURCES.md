# Speech integration sources

- Qwen model family and Apache-2.0 license: https://github.com/QwenLM/Qwen3-ASR
- Native Qwen runtime, Apache-2.0: https://github.com/soniqo/speech-swift (pinned revision in Package.swift and Xcode)
- Quantized local model: https://huggingface.co/aufklarer/Qwen3-ASR-0.6B-MLX-4bit
- Azure request specification: https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe
- BitVoice model variant licensing: https://huggingface.co/dhanr4j/bitvoice-dictation (Qwen3-0.6B Apache-2.0; other variants differ)
- SpeakoFlow mini: https://huggingface.co/SpeakoFlow/speakoflow-mini (Apache-2.0)
- Optional reference rules: https://github.com/AbhishekBarali/dictation-cleanup-rules (MIT; not bundled in SayStone)

Model weights stay in local application support and are not committed. Preserve upstream copyright/license notices when redistributing runtime code or weights. Microsoft MAI is a hosted provider, not a permissively licensed local model.
