# Decision records

One line per ruling. Code links here instead of quoting the conversation (rule 7 of `src/docs/docstring-standard.md`).

Format: `- YYYY-MM-DD · ID · Ruling in one sentence. · Who ruled · Source (path or row) · Applies to (paths)`

Rules: add a line, never edit an old one; to reverse a ruling, add a new line that names the old ID. Anything longer than one sentence belongs in a design document, linked from the Source field.

## Records

- 2026-09-30 · R5b-M1 · The Dart doc-comment standard is approved as drafted at `0fe024e`. · Rick (relayed by María 21:50 EDT; confirmed first-hand 2026-10-01) · lupin `src/rnd/v0.2.2/2026.09.30-lupin-af-documentation-rewrite-plan/2026.09.30-docs-rewrite-implementation-plan.md` §R.5b, row `b707f92f` · `src/docs/docstring-standard.md`
- 2026-09-30 · R5b-format · `dart format` is not a docs gate, because the house style (spaces inside parentheses and brackets) makes 536 of 539 files fail it; the house style stays. · Rick (confirmed first-hand 2026-10-01) · same plan, §R.5b · `lib/**`, `test/**`
- 2026-09-30 · R5b-AC-S1.10 · `lane_vocabulary_test` stops asserting doc-comment text and asserts behaviour or the existence of a record here; the `JobStatus` doc comment drops the bare `AC-S1.10` and links the record. · Rick (confirmed first-hand 2026-10-01) · same plan, §R.5b · `test/unit/queue/lane_vocabulary_test.dart`, `lib/shared/models/job.dart`

- 2026-09-30 · D8 · Doc contracts (Requires/Ensures) are required only where behaviour is not obvious; the coverage bar is zero `public_member_api_docs` hits per swept directory, and an `// ignore: public_member_api_docs` needs a same-line reason. · Rick (default stands until he sets another number at the M1 sign-off) · lupin `src/rnd/v0.2.2/2026.09.30-lupin-af-documentation-rewrite-plan/2026.09.30-docs-rewrite-implementation-plan.md` §14 · `lib/**`
- 2026-09-30 · D7 · History leaves code: it goes to the `Design:` document when one exists, otherwise to the commit message; `history.md` keeps session narrative only. · Rick · same plan, §14 · `lib/**`, `src/docs/**`
- 2026-09-22 · R1=B · The Holding Area groups held rows by persona with the session hash stripped, so all sessions of one persona share a group; the larger batch size is covered by `FilerGroup.ids` and `FilerGroup.count` coming from the same rows. · Rick · the doc block of `groupByFiler` at commit `cf5be6f` (`git show cf5be6f:lib/features/holding_area/data/holding_area_models.dart`) · `lib/features/holding_area/data/holding_area_models.dart`
