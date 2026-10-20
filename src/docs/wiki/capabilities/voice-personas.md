---
capability: voice-personas
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.notifications.data.voice_persona.VoicePersona@9c2345238e
  - lupin-mobile:lib.features.notifications.presentation.persona_badge.PersonaBadge@410907e6e4
  - lupin-mobile:lib.core.text.persona_label.personaLabel@165ad1cd4c
  - lupin-mobile:lib.core.text.persona_label.personaDisplayLabel@bdc9c20e5a
  - lupin-mobile:lib.features.notifications.data.notification_models.SpeakerphoneRecord@54eb777ac2
  - lupin-mobile:lib.features.notifications.domain.notification_state.PersonaSnapshotMixin@5712b8cd77
  - lupin-mobile:lib.features.notifications.domain.notification_state.SpeakerphoneSnapshotMixin@ac604106e0
---
# Voice personas

A voice persona is the named voice and badge the server gives each Claude Code session. This page covers the carrier class, the round badge, the rule for naming a stored persona string and the speakerphone record. The server half is lupin's `voice-persona-allocation` page.

## What it does
- `VoicePersona` is a passive carrier. `fromJson` never throws, missing fields become null, and `borrowed` and `overflow` default to false. Two personas are equal when `voiceId` matches.
- `PersonaBadge` draws the icon on its colour in a circle. Overflow gets a dotted border and an asterisk, borrowed gets a dashed border, and overflow wins. A null persona draws nothing.
- `PersonaBadge.colorOf` parses `#RRGGBB` or `#AARRGGBB`. A bad hex falls back to the theme's primary colour.
- `personaLabel` turns a stored `<persona> <8-hex session>` string into the persona name and keeps two-word names. With no session suffix the string comes back untouched.
- `personaDisplayLabel` also upper-cases each word start, the web rule, so it is safe as a grouping key.
- `NotificationBloc` keeps a persona per sender and copies a frozen snapshot into each loaded state. `PersonaSnapshotMixin` adds `personaFor`; `SpeakerphoneSnapshotMixin` adds `speakerphoneFor`.

## Don't
- Don't use `split( " " ).first` on a stored persona. It renders "mr radio" as "mr". Call `personaLabel`.
- Don't read the persona map to pick a voice. Speech takes the persona off each notification; see [[tts-streaming]].

## Invariants
- A state that is not a loaded view carries no snapshot, and the next loaded state picks the map up.
- The speakerphone record is diagnostic, and no screen reads it. The bloc [[focus-mode-chat]] keeps its own persona map.
