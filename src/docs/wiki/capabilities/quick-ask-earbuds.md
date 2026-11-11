---
capability: quick-ask-earbuds
pin_algorithm: py3.13.x6a05a1/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.quick_ask.presentation.earbud_hands_free.EarbudHandsFree@7cd0d34285
  - lupin-mobile:lib.features.quick_ask.domain.earbud_taps.EarbudGesture@cf393c96eb
  - lupin-mobile:lib.features.quick_ask.domain.earbud_taps.EarbudTapReader@ef50c13de5
  - lupin-mobile:lib.features.quick_ask.domain.earbud_taps.HandsFreeCue@efe9d4e6fc
  - lupin-mobile:lib.features.quick_ask.domain.earbud_taps.earbudAction@d103edf1c6
  - lupin-mobile:lib.features.quick_ask.data.hands_free_cues.CueTones@fc500dc4bb
  - lupin-mobile:lib.features.quick_ask.data.hands_free_cues.HandsFreeCuePlayer@24033b59bd
  - lupin-mobile:lib.features.quick_ask.data.hands_free_cues.ToneCuePlayer@488450d6eb
---
# Quick ask earbuds

Hands-free Quick Ask: while the screen is mounted, a tap on the earbud records and a double tap sends, with a tone for each outcome. The screen, bloc and state are in [[quick-ask]]. The media session that hands over the presses is in [[podcast-playback]].

## What it does
- `EarbudHandsFree` wraps the screen. While mounted it claims the earbud presses from the media session and plays the `ready` tone once it has them.
- `EarbudTapReader` turns presses into an `EarbudGesture`. A next-track press is a double at once. Two play or pause presses inside 400 ms are a double. A lone press is a single after that window. Previous-track is ignored.
- `earbudAction` does only what the on-screen buttons do. A single tap is the record button. A double tap is send, or stop while recording, so the question is not lost.
- A gesture that cannot act plays the `refused` tone and sends no event.
- `HandsFreeCue` names the tones: ready, started, stopped, sent, refused. The phone may not be in view, so each outcome has a sound.
- `CueTones` builds the tones as mono 16-bit WAV bytes. `ToneCuePlayer` plays them on the media stream and cuts off one still playing.

## Don't
- Don't map a gesture to anything the on-screen buttons cannot do.
- Don't wait for a tone to end before the next action. `HandsFreeCuePlayer.play` returns at once.

## Invariants
- `earbudAction` returns a null event exactly when the cue is `refused`, and never returns `ready`, which only the claim plays.
