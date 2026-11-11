---
capability: podcast-from-viewer
pin_algorithm: py3.13.x6a05a1/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.docs.data.doc_podcast.DocPodcastFacts@6e57fdb01a
  - lupin-mobile:lib.features.docs.data.doc_podcast.DocPodcastStarted@c0c47e51a4
  - lupin-mobile:lib.features.docs.data.doc_podcast.podcastRefusalText@46319c3fc9
  - lupin-mobile:lib.features.docs.presentation.podcast_confirm_sheet.showPodcastConfirmSheet@44fc500cd3
---
# Podcast from the doc viewer

The doc viewer's podcast button asks the server whether a file can be made into a podcast, confirms with the listener, then starts the job. The viewer is in [[doc-viewer-client]]; the finished audio is in [[podcast-library]].

## What it does
- `DocPodcastFacts` is the server's answer to the check, `GET /api/podcast-proxy/from-viewer/check`: the file's name and size in bytes. A missing or non-numeric size reads as 0.
- `showPodcastConfirmSheet` asks "Podcast <name>?" in an in-app bottom sheet, never a system dialog.
- `DocPodcastStarted` is the answer to `POST /api/podcast-proxy/from-viewer`: the queue job id. It is `spent` when the server answered 409, because this file's bytes already have a job.
- `podcastRefusalText` gives the server's own message when it sent one, from `{ detail: { code, message } }`. Otherwise it reads "Podcast failed (HTTP <status>)".

## Don't
- Don't show a second job for a spent file. The earlier job id comes back instead.

## Invariants
- The data classes import neither Flutter nor IO, so they run without a widget harness.
