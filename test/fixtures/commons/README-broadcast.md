# Broadcast (Phase 5) fixtures — and where each one actually came from

Two of these were captured from a live `:7999`. Three were **transcribed from the
producer source** because capturing them was either outward-facing or impossible from
this seat. That distinction is recorded per file below, and it is the point of this
README: a fixture labelled "captured" gets trusted without re-checking, so one that was
transcribed must never wear that label.

Regenerate the captured pair with:

```bash
export LUPIN_TEST_INTERACTIVE_MOCK_JOBS_EMAIL="..."
export LUPIN_TEST_INTERACTIVE_MOCK_JOBS_PASSWORD="..."
python src/scripts/capture-broadcast-fixtures.py
```

| file | provenance | why |
|---|---|---|
| `active_sessions.json` | ✅ **CAPTURED** live, 2026-09-22 | `GET /api/commons/active-sessions` |
| `broadcast_history.json` | ✅ **CAPTURED** live, 2026-09-22, `limit=5` | `GET /api/commons/broadcast-history` |
| `broadcast_history_disabled.json` | ⚠️ **TRANSCRIBED** from `commons.py` | needs the INI kill-switch flipped on shared infra |
| `broadcast_send_queued.json` | ⚠️ **TRANSCRIBED** from `commons.py` | a real send messages every live seat |
| `broadcast_send_no_sessions.json` | ⚠️ **TRANSCRIBED** from `commons.py` | same, and needs an empty fleet |
| `broadcast_ack_frame.json` | ⚠️ **TRANSCRIBED** from `commons_ack_watcher.py` | only exists after a real send |
| `broadcast_acks_saved.json` | ⚠️ **TRANSCRIBED** from `notifications.py` | only exists after a real send, and needs acks already in the DB |

## The captured pair

**`active_sessions.json`** — `{ "sessions": [ … ] }`, each carrying `session_id`,
`sender_id`, `persona_name`, `persona_icon`, `persona_color`, `last_seen_iso`,
`speakerphone_on`.

🔴 **The session COUNT is load-bearing and redaction must not change it.** Send is
disabled on `hasBody && hasRecipients`, so this number is half the button's enabled
condition. The capture script redacts identity value-for-value and never adds or drops a
session.

**`broadcast_history.json`** — `{ "entries": [ … ], "since_used", "next_cursor" }`.

⚠️ **Captured with an explicit `limit=5`, and that is this phase's own lesson applied to
its own tooling.** The server default is 200; a capture at the default pulled **144 KB of
real fleet traffic** into the repo. The pane must pass an explicit limit for the same
family of reason the ack drain must — so the fixture does too.

## The transcribed three, and exactly what determines each

**`broadcast_history_disabled.json`** — `commons.py`, `get_broadcast_history`. The
`disabled` key is emitted **only** when the INI flag
`commons traffic visibility enabled` is false, and the whole branch is four literal keys:

```python
return JSONResponse( content={
    "entries"     : [ ],
    "since_used"  : None,
    "next_cursor" : None,
    "disabled"    : True,
} )
```

Nothing is inferred — the branch returns literals and the fixture is those literals.
⚠️ Note the live capture **does not carry a `disabled` key at all** when the feature is
on. A reader that defaults a missing key to `false` is correct; one that requires the key
is not.

**`broadcast_send_queued.json` / `broadcast_send_no_sessions.json`** — `commons.py`,
`execute_broadcast`, whose docstring names every shape it returns. Both are the
`http_status: 200` arms with `http_status` popped by the endpoint before it responds, so
the fixtures correctly do **not** contain that key. The two differ exactly as the source
does: `recipients: 0` with `status: "no-active-sessions"` when the recipient list comes
back empty, and `recipients: <n>` with `status: "queued"` after a fanout.

⚠️ `status: "queued"` **is not a delivery receipt.** It is the same
paint-it-done-before-the-server-agrees hazard the 202 sentinel exists for on the task
panes. `failed_recipients` is the field that says otherwise and it must be read.

**`broadcast_ack_frame.json`** — `commons_ack_watcher.py`, `_push_ack_event`, wrapped in
the `notification_queue_update` envelope that `app.dart` dispatches on.

🔴 **`message` is an EMPTY STRING by design, and every field that makes an ack an ack
lives in `payload`.** The watcher passes exactly seven payload keys: `broadcast_id`,
`session_id`, `persona_name`, `persona_icon`, `persona_color`, `status`, `body_summary`.
A reader that goes looking in `message` finds nothing and reports zero acks.

⚠️ **This frame arrives ONLY over the socket.** It is not recoverable from
`GET /api/notifications/undelivered` — that is the finding behind this phase's acceptance
clause (store row `384591dd`; two independent code traces, plus a measurement that
`_log_to_io_tbl` never receives `payload` at all, so the io_tbl row for an ack is a type
label and an empty string). The surrounding envelope fields here follow the shape of
`test/fixtures/notifications/notification-with-persona.json`, which **is** a real capture.

⇒ If someone later runs a real broadcast with a person's go-ahead, **replace this file
with the capture and delete this paragraph.** Until then it is one careful reading of the
producer, which is a weaker class of evidence than a run and is labelled that way.

**`broadcast_acks_saved.json`** — `notifications.py`, `_project_broadcast_ack` (:2398)
wrapped in the `get_broadcast_acks` response (:2441). Every key in each ack row is one
line of that projection, in its order; the four envelope keys are the literal dict the
endpoint returns.

🔴 **THE STATUS KEY IS `ack_status` HERE AND `status` ON THE SOCKET FRAME.** The
projection lifts the identity fields out of `payload` onto the envelope and renames
`payload.status` on the way, because the envelope already carries a `state` of its own —
which is the notification's DELIVERY state, not the ack's. Both appear in this fixture,
deliberately and with different values, because a reader that grabs the wrong one still
produces a tally of the right SIZE and is therefore not caught by counting.

⚠️ **One row has `state: "delivered"` and that is the point of the endpoint.** The
undelivered drain would skip it; this read does not filter on delivery state at all
(`get_latest_acks_for_broadcast`, `notification_repository.py:653`). An ack that landed
while the app was open is marked delivered instantly, so a recovery built on the
undelivered inbox gets nothing back — the fixture carries both states so a regression
toward that filter fails here.
