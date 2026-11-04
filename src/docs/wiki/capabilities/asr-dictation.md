---
capability: asr-dictation
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.services.asr.asr_service.AsrException@c9ccd96e88
  - lupin-mobile:lib.services.asr.asr_service.AsrService@7fdacc2ee9
  - lupin-mobile:lib.services.asr.dictation_splice.spliceDictation@f35ab13be4
  - lupin-mobile:lib.services.asr.voice_capture_session.VoiceCaptureSession@e4bb43605d
  - lupin-mobile:lib.services.asr.voice_capture_session.VoiceCapture@ec23df4279
  - lupin-mobile:lib.services.asr.voice_capture_session.VoiceCaptureStart@c737374c86
  - lupin-mobile:lib.services.permissions.mic_permission.requestMicPermission@5dd4ce4986
  - lupin-mobile:lib.shared.models.voice_input.VoiceInputStatus@877275c882
  - lupin-mobile:lib.shared.models.voice_input.AudioFormat@9abe0aed42
  - lupin-mobile:lib.shared.models.voice_input.VoiceInput@67c78e7441
  - lupin-mobile:lib.shared.widgets.dictation_text_field.DictationPhase@069426c12b
  - lupin-mobile:lib.shared.widgets.dictation_text_field.DictationRecorderGuard@0139a2436e
  - lupin-mobile:lib.shared.widgets.dictation_text_field.DictationScope@4a7a0f70a5
  - lupin-mobile:lib.shared.widgets.dictation_text_field.DictationTextField@bfb8f367bf
---
# Speech to text and dictation

`AsrService` records the microphone, uploads the audio and returns the transcript. `VoiceCaptureSession` is the shared record-and-review wrapper, and `DictationTextField` is the text box with an append mic. See [[tts-streaming]], [[http-client]] and [[focus-mode-chat]].

## What it does
- `AsrService` posts to `POST /api/v2/transcribe` through the shared `Dio`, so the bearer rides along. It answers a transcription and a trace with timings. Capture start and end call `TtsOrchestrator.setCaptureHold`, so no notification speaks over a recording.
- It records Ogg/Opus, mono, 32 kbps at 48 kHz. A device with no Opus encoder falls back to 16-bit PCM WAV at 44100 Hz.
- Every failure is an `AsrException`: a denied permission, a recorder failure, a non-200 reply, a network failure or an empty transcript. An empty reply is an error, never a blank field.
- `VoiceCaptureSession.start()` asks for the microphone, then records. `stopAndTranscribe()` returns a `VoiceCapture`. A cancel bumps a counter, so a late result from an earlier attempt is dropped.
- Focus mode and Quick Ask both use the session. Only Quick Ask's own job tracking stays in its bloc.
- `spliceDictation` places a dictated chunk in a box. It appends at the caret and never replaces text, and a blank chunk changes nothing.
- `DictationTextField` runs the idle, listening and transcribing phases (`DictationPhase`) for any text box. `DictationScope` hands it the service from the app root.
- `DictationRecorderGuard` allows one recorder at a time per service. A second mic press is disabled and never stops the first.
- `requestMicPermission` returns true when recording is allowed. `VoiceInput` models one attempt from recording to transcript.

## Don't
- Don't use the MP3 upload endpoint for chat replies. It queues a multimodal job and returns no transcript.
- Don't replace a box's text with a dictated chunk. The user may have typed half the message.
- Don't let a field take a session from its ancestors. The widget builds its own, so its lifetime is its own.
- Don't treat a recording as clean because it is non-empty. Whisper can invent text on silence.
