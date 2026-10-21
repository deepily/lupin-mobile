---
capability: live-transcript
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.transcript.data.transcript_repository.TranscriptRepository@09cbf3c45e
  - lupin-mobile:lib.features.transcript.domain.transcript_stream_bloc.TranscriptStreamBloc@d04cce530a
  - lupin-mobile:lib.features.transcript.domain.transcript_frame_router.TranscriptFrameRouter@653045d452
  - lupin-mobile:lib.features.transcript.data.transcript_models.TranscriptBlock@348a7d7377
  - lupin-mobile:lib.features.transcript.data.transcript_models.TranscriptBlockKind@be810b59b4
  - lupin-mobile:lib.features.transcript.data.transcript_models.TranscriptAppend@1ce8200505
  - lupin-mobile:lib.features.transcript.data.transcript_repository.TranscriptRefused@01cca107ff
  - lupin-mobile:lib.features.transcript.presentation.live_console_screen.LiveConsoleScreen@eac7a393fa
  - lupin-mobile:lib.features.transcript.presentation.transcript_block_view.TranscriptBlockView@b39bb7625f
  - lupin-mobile:lib.features.transcript.domain.transcript_stream_bloc.TranscriptViewState@c531ad5541
  - lupin-mobile:lib.features.transcript.data.transcript_models.TranscriptStreamState@815a780632
  - lupin-mobile:lib.features.transcript.data.transcript_repository.TranscriptApiException@19502d0360
  - lupin-mobile:lib.features.transcript.domain.transcript_stream_bloc.TranscriptAppendReceived@5e950caf2e
  - lupin-mobile:lib.features.transcript.domain.transcript_stream_bloc.TranscriptBacklogLoaded@65aec088ad
---
# Live transcript

The Live Console: one Claude Code seat's transcript, read-only, as display blocks. It reads a REST backlog, then follows a WebSocket tail. Lupin's server half is the `session-transcript-console` page. The Watch button on a seat's row in [[fleet-status]] opens it. Detail pages: [[transcript-stream-events-and-frames]].

## What it does
- `TranscriptRepository` reads `/api/cc-transcript/...`: the opening tail, a forward read from an offset, a backwards page and one block's full text. A 403 raises `TranscriptRefused`.
- Each `fromJson` on `TranscriptBlock` and `TranscriptAppend` never throws. `TranscriptBlockKind` has text, tool call, tool result, thinking and unknown, and only text goes through markdown.
- `TranscriptFrameRouter` is the app-root seam. It forwards `cc_transcript_append` and `cc_transcript_state` frames to the one open console for that seat and drops the rest.
- `TranscriptStreamBloc` is created by the route and closed with it. It reads the tail, then sends `cc_transcript_watch` from the response's `next_offset`. Closing it sends `cc_transcript_unwatch` once per watch.
- A chunk whose offset does not abut the last one is dropped, and the gap is fetched over REST. A changed epoch, from `/clear` or a shrunken file, clears the buffer and reads a fresh tail.
- `refused` is terminal and shows a static message with Back only. The buffer holds 256 KB, oldest evicted first.
- `LiveConsoleScreen` lists newest at the bottom, with Load earlier at the top. `TranscriptBlockView` collapses tool calls, results and thinking.

## Don't
- Don't make the bloc an app-root singleton. It would keep the server watch open after the operator left.
- Don't append after a gap or a stale epoch. Drop, clear or repair.
- Don't pass the 8-character session prefix. The console needs the full session id.

## Invariants
- A frame never reaches another seat's console, and a refusal is never retried.
