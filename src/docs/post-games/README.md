# Post-games

Retrospectives of finished runs, one folder per work-branch version. The workflow that produces them is planning-is-prompting `workflow/post-game.md`; section 5.6 defines this folder.

- **Where a retro goes:** `src/docs/post-games/<version>/yyyy.mm.dd-<slug>-post-game.md`, where `<version>` is the work branch's version (`v0.2.2` while the branch is `wip-v0.2.2-…`).
- **Frontmatter:** `manager: <persona>`, the manager who ran the engagement.
- **Tracked:** these files are committed. Logs, failsets, screenshots and data dumps are cited, never checked in.
- **Lifetime:** a retro is kept while its version is the current work. Its lessons outlive it by graduating into a workflow doc, the Decisions Log or a store row. Deleting an older version's folder is the owner's call.
- **Older retros:** post-games written before 2026-10-03 are in `src/rnd/` and stay there.

## Index

Register every full retro here when it is written.

| Date | Version | Engagement | Manager | Type | Key threads | Rulings | Graduated to |
|---|---|---|---|---|---|---|---|
| 2026.10.09 | v0.2.2 | [Board-whittling crew](v0.2.2/2026.10.09-board-whittling-crew-post-game.md) | Tiffany | SWE-crew run (four seats, one morning, two more in the afternoon), written after the manager's own context clear from commits, verdict files, gate logs and mementos; no rolling deposits, nobody cross-examined | reviewer refused the manager's masking ruling · one of two cross-repo test files run · estimated clock times · handover dropped a row blocked on me · seat with no persona · merges queued behind the gate | R12 to R18, drafted, waiting for Rick | none yet; lupin row `879fe139` (held) |
| 2026.10.03 | v0.2.2 | [Deletion, warnings and merge gate crew](v0.2.2/2026.10.03-deletion-warnings-merge-gate-crew-post-game.md) | Tiffany | SWE-crew run (three workers, one afternoon), written from 12 rolling deposits and a live cross-examination of the reviewer | gate green on its own range · hollow refusal tests · instance fixes · deletion checked by imports alone · permission refusals · size standing in for completeness | R6 to R11, drafted, waiting for Rick | none yet; rows `91c260ef`, `08d4c9fb` |
| 2026.10.03 | v0.2.2 | [Mobile docs track crew](v0.2.2/2026.10.03-mobile-docs-track-crew-post-game.md) | Tiffany | SWE-crew run (five seats over three days), written from mementos and receipts | gate held hostage by a re-spin · gate built on an unmeasured predicate · dead module swept · no rolling deposits | R1 to R5, approved by Rick 2026-10-03 | `TODO.md` Decisions Log 2026-10-03; row `00db303b` (R1) |
