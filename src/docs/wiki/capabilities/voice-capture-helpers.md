---
capability: voice-capture-helpers
pin_algorithm: py3.13.x6a05a1/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.services.asr.peak_meter.PeakMeter@3277960f2d
  - lupin-mobile:lib.features.focus_mode.presentation.voice_reply_field.VoiceReplyField@2088dbfe93
  - lupin-mobile:lib.services.diagnostics.earbud_trace_uploader.EarbudTraceUploader@627f3a8aff
---
# Voice capture helpers

Three small helpers around recording: a level meter, a reply composer and an earbud trace uploader. The recorder and transcription are in [[asr-dictation]]. The earbud taps they trace are in [[quick-ask-earbuds]].

## What it does
- `PeakMeter` reads the recorder's level every 100 ms during a capture and keeps the loudest, in decibels from 0 down to about -160. A silent capture is transcribed as "thank you", so the level shows in the trace first.
- `PeakMeter.describe` gives the trace line: the peak, the reading count and whether the capture looks silent, below -50 dB. A reading that throws or is null is skipped.
- `VoiceReplyField` is a self-contained composer: idle, recording, transcribing, review, then idle. Send calls `onSubmit` once with the edited text. It never dispatches the response itself.
- Transcribing shows a spinner and can be cancelled. Any `AsrException` shows an inline error and returns to idle.
- `EarbudTraceUploader` is a log destination. It sends each earbud trace line as `GET /health?earbud_trace=<line>`, so the line shows in the server's access log without adb.
- It uses its own bare `Dio`, and `install` leaves exactly one uploader on the logger. A failed or offline upload is dropped silently.

## Don't
- Don't give the uploader the shared `Dio`. A 401 on `/health` would start a token refresh or a sign-out.
- Don't decide whether the composer shows. That gate belongs to the parent.
