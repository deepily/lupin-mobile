---
capability: artifact-viewers
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.artifacts.audio_artifact_player.AudioPlaybackController@3c3686b132
  - lupin-mobile:lib.features.artifacts.audio_artifact_player.AudioArtifactPlayer@2680b69eb6
  - lupin-mobile:lib.features.artifacts.markdown_report_viewer.MarkdownReportViewer@e0b63ed659
  - lupin-mobile:lib.features.artifacts.slide_deck_viewer.SlideDeckViewer@da37c867bb
  - lupin-mobile:lib.services.artifacts.io_file_service.IoFileService@17a712cf26
  - lupin-mobile:lib.services.artifacts.io_file_service.IoFileException@d77a03a270
---
# Artifact viewers

Three full-screen viewers for what a finished job produced, plus the service that downloads the file. The job detail screen picks the viewer by job id prefix. Lupin's `doc-viewer` serves the `/api/io/file` door.

## What it does
- Prefix `dr-` opens `MarkdownReportViewer` on the fetched report. `pg-` and `rp-` open `AudioArtifactPlayer` on the job's report path. `px-` and `rx-` open `SlideDeckViewer` on its pptx path. Other prefixes open nothing.
- `MarkdownReportViewer` renders selectable markdown and shares `<jobId>-report.md`.
- `SlideDeckViewer` downloads `<jobId>.pptx` and opens or shares it in another app. There is no in-app slide rendering.
- `AudioArtifactPlayer` downloads `<jobId>.mp3`, then plays, pauses and stops. Seek is read-only. It calls `TtsOrchestrator.stopAll` first, so only one audio stream plays ([[tts-streaming]]).
- `AudioPlaybackController` wraps `audioplayers` so widget tests can swap it.
- `IoFileService` calls `GET /api/io/file?path=...`, writes to the temporary directory, then shares or opens. `IoFileException` carries the HTTP status.

## Don't
- Don't fetch artifacts with a second Dio call; use `IoFileService.downloadToCache`.
- Don't trust the `.pptx` name: every deck download uses it, even a PDF.

## Invariants
- An empty audio path shows an error and makes no request.
- The player shows Retry; the deck viewer shows a red snackbar.
- `openExternalApp` raises unless the OS reports the file opened.
- A second download of one job overwrites the first.
