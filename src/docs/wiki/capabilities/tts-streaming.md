---
capability: tts-streaming
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.services.tts.speech_intent.isActionableQuestion@6c57a23748
  - lupin-mobile:lib.services.tts.speech_intent.shouldSpeakVerbatim@3b7abd1416
  - lupin-mobile:lib.services.tts.streaming_tts_player.StreamingTtsAudioPlayer@10f8586070
  - lupin-mobile:lib.services.tts.streaming_tts_player.StreamingTtsPlayer@9dd7ed669e
  - lupin-mobile:lib.services.tts.streaming_tts_player.TtsStatusEvent@c60769e704
  - lupin-mobile:lib.services.tts.streaming_tts_player.TtsCompleteEvent@151378f6af
  - lupin-mobile:lib.services.tts.streaming_tts_player.TtsErrorEvent@0059294468
  - lupin-mobile:lib.services.tts.tts_orchestrator.TtsOutcome@00a65fe3ab
  - lupin-mobile:lib.services.tts.tts_orchestrator.TtsOrchestrator@6d442ea253
  - lupin-mobile:lib.services.tts.tts_orchestrator.TtsSender@6a01129142
  - lupin-mobile:lib.services.tts.tts_orchestrator.TtsSuppression@179de0276e
  - lupin-mobile:lib.services.tts.tts_orchestrator.TtsQueueItem@dc045be064
  - lupin-mobile:lib.services.tts.tts_preview_truncator.TtsPreviewTruncator@3b95515188
---
# Text-to-speech playback

`TtsOrchestrator` is the single queue every spoken message goes through, so only one voice plays at a time. `StreamingTtsPlayer` fetches ElevenLabs audio from the server and plays it. When ElevenLabs fails, the orchestrator speaks on the device. See [[notification-audio-playback]], [[focus-mode-chat]] and [[asr-dictation]]. The chunk record for cached audio is on [[tts-audio-chunk-model]].

## What it does
- `enqueueAlways` is the focus-surface entry point and speaks every notification. `enqueueIfSpeakable` is the legacy gated one, whose production dispatch is withdrawn at the DI seam.
- Two gates apply to ordinary chatter: the user's stop-list, then a system-sender switch. A message the user must act on is `verbatim` and skips the sender gate and the fraction cut, but never the stop-list.
- A stop-list refusal comes back as a `TtsSuppression` on `suppressedStream`. `speakAnyway` re-issues it. `TtsOutcome` gives a plain line saying why a message stayed silent.
- `TtsPreviewTruncator` speaks about a fraction of each message, ending at the next sentence boundary. A message under its minimum length is spoken whole, and a fraction of zero means silence.
- `pause()` holds the queue without dropping anything. `setCaptureHold( true )` also holds it while the microphone records.
- An urgent message preempts a non-urgent one that is playing, and the interrupted one requeues behind it. While paused it only queues.
- `StreamingTtsPlayer.speak( text )` posts to `/api/get-speech-elevenlabs`. The audio arrives as WebSocket chunks and plays once as one PCM blob. `TtsCompleteEvent` fires after playback ends.
- A `quota_exceeded` error switches to `flutter_tts` for 5 minutes. `queueStream` feeds the queue viewer with skip, remove and clear.

## Don't
- Don't fire completion before playback ends. The next `play()` would cut the current utterance.
- Don't send the persona `voiceId` to the `flutter_tts` fallback. Its voice space differs.
- Don't drop a message when paused. Hold it.

## Invariants
- A watchdog speaks on the device when an utterance gets no audio event for too long. A lost completion event cannot block the queue.
