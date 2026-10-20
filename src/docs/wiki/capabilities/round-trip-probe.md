---
capability: round-trip-probe
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.settings.presentation.round_trip_probe_screen.RoundTripProbeScreen@76211ed06f
  - lupin-mobile:lib.services.diagnostics.probe_wav.ProbeWav@06eb376eee
  - lupin-mobile:lib.services.diagnostics.round_trip_probe.ProbeSink@03b2021875
  - lupin-mobile:lib.services.diagnostics.round_trip_probe.FileProbeSink@99f0677296
  - lupin-mobile:lib.services.diagnostics.round_trip_probe.openProbeFileSink@2c36fd3f1c
  - lupin-mobile:lib.services.diagnostics.round_trip_probe.networkTypeName@eb0dbca9da
  - lupin-mobile:lib.services.diagnostics.round_trip_probe.connectivityNetworkType@32591f9271
  - lupin-mobile:lib.services.diagnostics.round_trip_probe.ProbeSample@a6b11a367b
  - lupin-mobile:lib.services.diagnostics.round_trip_probe.ProbeGroupSummary@36dd562898
  - lupin-mobile:lib.services.diagnostics.round_trip_probe.ProbeResult@9a2fe2399e
  - lupin-mobile:lib.services.diagnostics.round_trip_probe.RoundTripProbe@315a20ba35
---
# Round-trip probe

`RoundTripProbe` measures how long real requests take through the app's own HTTP stack and writes one JSON line per request. `RoundTripProbeScreen` runs it from the Debug section of the notification audio settings, which shows in release builds too. See [[http-client]] and [[asr-dictation]].

## What it does
- A run sends 20 sequential `GET /health` calls, then 3 timed uploads of a 30 second WAV at 44100 Hz and at 16000 Hz. That is 26 requests (`totalRequests`).
- It uses the injected `Dio`. In the app that is the shared one, so the auth interceptor and the HTTP service interceptors are part of what is measured.
- Uploads go to `AsrService.endpointPath`, the transcription endpoint. They do not submit a job.
- `ProbeWav` builds the clip in memory: a linear sweep from 220 Hz to 1760 Hz, mono, 16-bit PCM, the same bytes every time. Nothing is bundled in the APK.
- Each request becomes a `ProbeSample`: start time, kind (`health` or `upload`), network type, total milliseconds, status and any failure. An upload also records its size and `send_ms`.
- An upload's total includes transcription time, because the endpoint transcribes before it answers. Its record says so with `total_ms_includes_transcription`.
- `ProbeResult` holds the samples, a `ProbeGroupSummary` per group (median, 90th percentile, maximum and failure count) and the network types seen. `cancelled` is true for an early stop.
- `FileProbeSink` writes `round-trip-probe-<yyyyMMdd-HHmmss>.jsonl` in the app support directory. `probeLogPullHint` gives the `adb` command that copies it off a debug build.
- `networkTypeName` maps a connectivity result to `wifi`, `mobile`, `other` or `none`.

## Don't
- Don't write the log to external storage. Since Android 11, `adb pull` cannot read it.
- Don't read an upload's total as network time alone. It includes server transcription.
- Don't treat a null `send_ms` as zero. It carries a reason: unknown body length, or send progress never completed.

## Invariants
- Percentiles use the nearest rank, so each one is a measured value. An empty group gives null.
