---
capability: heartbeat-and-push-switches
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.settings.data.heartbeat_poke_repository.HeartbeatPokeState@c308651e1b
  - lupin-mobile:lib.features.settings.data.heartbeat_poke_repository.HeartbeatPokeRepository@375e92a2ba
  - lupin-mobile:lib.features.settings.data.heartbeat_poke_repository.HeartbeatPokeException@ec4a0a24e6
  - lupin-mobile:lib.features.settings.data.push_pause_repository.PushPauseState@7fe737adbe
  - lupin-mobile:lib.features.settings.data.push_pause_repository.PushPauseRepository@16c7dd33b6
  - lupin-mobile:lib.features.settings.data.push_pause_repository.PushPauseException@2d4d0f6669
  - lupin-mobile:lib.features.settings.presentation.heartbeat_poke_section.HeartbeatPokeSection@3cf8a1ca05
  - lupin-mobile:lib.features.settings.presentation.push_pause_section.PushPauseSection@abe863e4dd
---
# Heartbeat and push switches

Two settings sections flip fleet-wide server switches from the phone: the heartbeat stop poke and the push pause. Each has a repository for one route and a section widget on the notification management screen.

## What it does
- `HeartbeatPokeRepository` reads and writes `/api/heartbeat/poke-mute`. `getState` is a GET; `setMuted` PUTs `{"muted": <bool>}`.
- `PushPauseRepository` uses `/api/fcm/push-pause`. `pause( minutes: )` POSTs `paused: true` and sends `minutes` only when it is not null. `resume` POSTs `paused: false`.
- `PushPauseRepository.maxMinutes` is 1440. The server refuses more with a 400; the client does not check.
- `PushPauseSection` offers 30 min, 1 h, 2 h, 8 h, 24 h and "Until I resume", which sends no `minutes`.
- Any signed-in user may read either switch. Only an admin may write. A 403 sets `isAdminOnly` on the exception.

## Don't
- Don't cache either state. Any client can flip the poke, and a server restart clears the push pause. Both sections re-read on open and on each foreground.
- Don't read a good GET as proof of admin rights. After one admin-only refusal the heartbeat section stays disabled until the screen reopens. The push pause section clears it after any successful action.
- Don't read `muted` or `paused` as anything but a JSON `true`. A malformed body reads as not muted and not paused.

## Invariants
- `muted` false means sessions are poked when they stop with work owed. The poke switch has no timer.
- A null `resumesAt` while paused means the pause lasts until resumed or the server restarts.
- `set_at` and `resumes_at` are parsed to the phone's local zone.
- Both sections route every call through one wrapper that handles busy, error and 403, so no failure crashes the screen.
- Skeleton crew is a different switch, beside the cap dial in [[fleet-status]]. Push delivery itself is [[fcm-push-wake]].
