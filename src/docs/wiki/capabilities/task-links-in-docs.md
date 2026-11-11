---
capability: task-links-in-docs
pin_algorithm: py3.13.x6a05a1/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.docs.data.task_link.TaskLink@a57a1968ad
  - lupin-mobile:lib.features.docs.data.task_link.TaskLinkKind@ee2762b9a7
  - lupin-mobile:lib.features.docs.data.task_link.classifyTaskHref@bd385a6850
  - lupin-mobile:lib.features.docs.presentation.task_link_markdown.TaskLinkMarkdown@459262f88f
  - lupin-mobile:lib.features.docs.presentation.task_link_markdown.TaskLinkPhase@cef73162b4
  - lupin-mobile:lib.features.docs.presentation.task_link_markdown.TaskLinkSession@7c51ff277f
  - lupin-mobile:lib.features.docs.presentation.task_link_markdown.TaskLinkState@f6ba9d4536
  - lupin-mobile:lib.features.docs.presentation.task_link_markdown.taskOverlayText@40ecca17f4
---
# Task links in documents

A card abstract can carry approve and view links for held task rows, and the app acts on them in place. Other links go to the usual handler in [[doc-viewer-client]]. The row reads and the approve move use the task repositories in [[task-list-data]].

## What it does
- `classifyTaskHref` recognises a task link by its address, never its label. Only `/app/tasks/approve` and `/app/tasks/view` match, each with a full lowercase row uuid. Anything else gives null and sends nothing.
- `TaskLinkMarkdown` draws markdown so that approve links act in place. With no repository the task links stay ordinary links.
- `TaskLinkSession` lives as long as the drawn card. It reads each row once, however many links name it, and sends at most one approve per row at a time.
- A `TaskLinkState` has one of five `TaskLinkPhase` looks: live, sending, approved, closed or refused. Every link that names the row shares it.
- A held row (`not_approved`), an empty status or a failed read leaves the link live. Any other status, even an unknown one, shows approved, except dropped or wont_fix, which show that status as plain text.
- A refusal or a closed status is drawn as selectable plain text under the card, so the server's words stay exact.
- A view link opens `taskOverlayText` in a dialog: title, priority, owner, status and body. A missing field reads as a dash, `unowned` or `(no body)`.

## Don't
- Don't send an approve for a link whose `row` is not a full uuid.
- Don't route a refusal through markdown. It would change the server's words.

## Invariants
- A link already tapped is never overwritten by a later read.
