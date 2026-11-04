---
capability: transcript-stream-events-and-frames
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.transcript.data.transcript_models.TranscriptStateFrame@1baad2af96
  - lupin-mobile:lib.features.transcript.data.transcript_models.TranscriptBacklog@4f834e2feb
  - lupin-mobile:lib.features.transcript.domain.transcript_stream_bloc.TranscriptEvent@4f1403f292
  - lupin-mobile:lib.features.transcript.domain.transcript_stream_bloc.TranscriptEarlierLoaded@34e67071b9
  - lupin-mobile:lib.features.transcript.domain.transcript_stream_bloc.TranscriptStateReceived@2514eb27c2
  - lupin-mobile:lib.features.transcript.domain.transcript_stream_bloc.TranscriptCleared@982032e5dc
  - lupin-mobile:lib.features.transcript.domain.transcript_stream_bloc.TranscriptFailed@a130637e36
  - lupin-mobile:lib.features.transcript.domain.transcript_stream_bloc.TranscriptRefusalReceived@d15d86e744
  - lupin-mobile:lib.features.transcript.domain.transcript_stream_bloc.TranscriptBlockFilled@0f0a9c9343
  - lupin-mobile:lib.features.transcript.domain.transcript_stream_bloc.TranscriptLoadingChanged@608f97e8d2
---
# Transcript stream events and frames

The state frame, the REST backlog body and the events `TranscriptStreamBloc` accepts, beyond those on [[live-transcript]].

## What it does
- `TranscriptStateFrame` is the `cc_transcript_state` frame: session id, file epoch, a `TranscriptStreamState`, the raw state string and an optional reason. An unrecognized state parses to unknown and the raw string is kept.
- `TranscriptBacklog` is the body of all four REST reads: epoch, start offset, next offset, blocks and `atStart`. A non-map body gives an empty backlog. A missing `atStart` is false, so Load earlier stays visible.
- `TranscriptBacklogLoaded` replaces the buffer on a fresh open or an epoch change, and appends on a catch-up or gap repair. `TranscriptEarlierLoaded` adds a backwards page.
- `TranscriptStateReceived` carries a state frame. `TranscriptCleared` drops the buffer and offset, naming the new epoch when there is one.
- `TranscriptFailed` is a retryable failure that keeps the buffer. `TranscriptRefusalReceived` is terminal and is never folded into the error.
- `TranscriptBlockFilled` swaps one truncated block for its full text by buffer index. `TranscriptLoadingChanged` sets the opening and earlier-page flags.

## Don't
- Don't treat a refusal as an error. A foreground return or a fresh login could then re-arm it.
- Don't read `lastNextOffset` as a count. It is the sequence cursor, and a chunk whose offset differs from it has a gap in front of it.
