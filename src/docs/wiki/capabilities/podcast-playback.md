---
capability: podcast-playback
pin_algorithm: py3.13.x6a05a1/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.services.audio.podcast_player_service.PodcastPlayerService@5d15ccfde8
  - lupin-mobile:lib.services.audio.podcast_player_service.PodcastPlayerStatus@6bcf56fe26
  - lupin-mobile:lib.services.audio.podcast_player_service.PodcastPlaybackEngine@faee7cdb33
  - lupin-mobile:lib.services.audio.just_audio_playback_engine.JustAudioPlaybackEngine@361679e4ee
  - lupin-mobile:lib.services.audio.lupin_media_handler.LupinMediaHandler@b828940078
  - lupin-mobile:lib.services.audio.lupin_media_handler.MediaButtonClaimant@3492fa69c1
  - lupin-mobile:lib.services.audio.lupin_media_handler.MediaTransport@cb6ca6977a
  - lupin-mobile:lib.services.audio.podcast_audio_session.configurePodcastAudioSession@4fe233e876
  - lupin-mobile:lib.features.audio.mini_player_bar.MiniPlayerBar@0591e5a06c
---
# Podcast playback

One app-wide player for podcasts, with a lock-screen card, earbud handling and a mini-player bar. Downloads and the file cache are in [[podcast-downloads]]; the list and the done card are in [[podcast-library]]. Earbud claims by Quick Ask are in [[quick-ask-earbuds]].

## What it does
- `PodcastPlayerService` lives for the life of the app, so audio keeps playing when the screen that started it is popped. Its status is idle, loading, playing, paused or error.
- `PodcastPlaybackEngine` is the seam over the platform player. `JustAudioPlaybackEngine` is the real one, built on `just_audio`, and tests inject a fake.
- The engine's `play` may stay pending until playback ends, so the service starts it without waiting. Awaiting it would hide the mini-player for the whole track.
- The service pauses the podcast while TTS speaks. `followSpeech` takes the orchestrator's speaking stream, and `resumeAfterSpeech` undoes only that pause.
- `configurePodcastAudioSession` uses the speech recipe, so a short spoken alert pauses the podcast instead of only ducking it.
- `LupinMediaHandler` is the one media session: the lock-screen card, and where earbud presses go. A press drives the podcast. The rewind key backs up 15 seconds and fast-forward jumps 10.
- A `MediaButtonClaimant` can hold the presses, and then shows its own card. A playing podcast always wins: a press pauses it.
- `MiniPlayerBar` sits at the bottom of every screen and is hidden while nothing is loaded. It has back 15 seconds (long-press: to the start), play or pause, and close.

## Don't
- Don't await `play` on the engine. It completes when playback ends or pauses.
- Don't let the podcast talk over speech. `pauseForSpeech` is the audio-focus ruling.

## Invariants
- `resumeAfterSpeech` does nothing if the listener paused, stopped or switched tracks in the meantime.
