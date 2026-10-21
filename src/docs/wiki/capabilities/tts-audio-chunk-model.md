---
capability: tts-audio-chunk-model
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.shared.models.audio_chunk.AudioChunk@1fcaca318c
  - lupin-mobile:lib.shared.models.audio_chunk.AudioChunkType@2fc5eb43c3
  - lupin-mobile:lib.shared.models.audio_chunk.AudioChunkStatus@ee192082e4
---
# Audio chunk model

`AudioChunk` is the record for one piece of streamed or cached audio, with the bytes and the playback state. Part of [[tts-streaming]]. The cache that stores it is in [[local-caches]].

## What it does
- It holds `data` (the encoded bytes), `type`, `status`, and optional `text`, `provider`, `voiceId`, `sequenceNumber`, `totalChunks`, `duration`, `sampleRate`, `bitRate`, `format` and `metadata`.
- `AudioChunkType` is `tts`, `voice`, `notification` or `system`. `AudioChunkStatus` is `pending`, `playing`, `completed`, `failed` or `cached`, and defaults to `pending`.
- `fromJson` and `toJson` use snake_case keys and write `data` as a list of integers. An unknown type reads as `tts` and an unknown status as `pending`.
- `isFirstChunk` is true at sequence 0. `isLastChunk` is false when the sequence number or the total is unknown.
- `canPlay` is true for `pending` and `cached`. Equality compares every field.

## Don't
- Don't look for it in the playback path. `StreamingTtsPlayer` and `TtsOrchestrator` never use it, and the only code in `lib/` that touches it is `AudioCache`.
- Don't expect `status` to move. Nothing in `lib/` outside this file changes or reads it.
- Don't rely on the cache size cap with these chunks. `AudioCache` sizes a chunk from `metadata["size_bytes"]` and counts 0 when it is absent.
