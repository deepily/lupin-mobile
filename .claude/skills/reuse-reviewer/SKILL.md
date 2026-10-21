---
name: reuse-reviewer
description: Review a lupin-mobile diff for code reuse. For every new Dart definition, fetch its similar existing symbols, read the shortlisted wiki pages and source, and rule DUPLICATE, EXTEND <symbol> or DISTINCT <why>, each citing a receipt id. Use in code review of any diff that adds a class, function, method or widget under lib/, or when asked "does this already exist?".
---

# Reuse reviewer (lupin-mobile)

Ported from lupin's `.claude/skills/reuse-reviewer/SKILL.md`. Advisory: the gating key `reuse review gating` lives in lupin's `src/conf/lupin-app.ini` and is `false`, so this skill reports and rejects nothing. Only Rick sets it to `true`.

**Mobile root:** `/mnt/DATA01/include/www.deepily.ai/projects/lupin-mobile`. Pass it as `root` on every reuse tool call (`check_exists`, `fetch_similar`, `read_capability`, `replay`). Without it the tools default to the git root of the working directory, which in a seat worktree is not the root the index was built for.

**Mobile wiki:** `src/docs/wiki/INDEX.md` lists the slugs; each page is `src/docs/wiki/capabilities/<slug>.md`. `read_capability( names=[ "<slug>" ], root=<mobile root> )` returns the page.

**Mobile index:** published under `/mnt/DATA01/include/www.deepily.ai/projects-data/lupin-mobile/reuse-review/index/lupin-mobile/current` (Dart, parsed by the analyzer; `header.json` names the pin algorithm). Ids look like `lupin-mobile:lib.core.cache.cache_manager.CacheHitEvent`. A constructor repeats the class name: `...CacheHitEvent.CacheHitEvent`. Only public symbols are in `symbols.jsonl`. Private ones (`_ErrorView`, `_SectionHeader`) are in `symbols-all.jsonl` and in `diff --all`, and `fetch_similar` looks them up like public ones.

## What to do

1. **List the new definitions.** Index the base and the head with lupin's tool, then diff them. `--all` includes private classes and nested helpers, where unplanned duplicates usually live.

   ```bash
   cd "$LUPIN_ROOT" && PYTHONPATH=src python -m cosa.repo.symindex build --root <mobile tree> --out <scratch dir>      # once per side; note the generation path it prints
   cd "$LUPIN_ROOT" && PYTHONPATH=src python -m cosa.repo.symindex diff <OLD_GEN> <NEW_GEN> --all > diff.json
   ```

   Always pass `--out` with a directory of your own, one per side. Without it builds from different seats share one directory per root name and overwrite each other.

   The new definitions are `added` in `diff.json`. If it holds `algorithm_changed`, rebuild both sides with one tool version and diff again. Treat a `changed` entry whose body grew a new nested helper as a new definition.

   **The index does not see every file.** Only Dart under `lib/` is indexed. Definitions in `tool/*.py`, `src/scripts/*`, `android/`, `test/` and generated files are never in `added`. List those from `git diff <base> <head> -- <file>` by hand, search the tree for a twin with a fixed-string search, and rule with the token `unindexed` (step 5).

2. **Ask the index, one definition at a time.** Call `fetch_similar( entry, root )` with the symbol id exactly as `diff.json` lists it. Keep the `receipt_id`. Pair it with the symbol you asked about, never with the position of the reply: parallel calls do not come back in the order they were sent, and the gate answers `WRONG_RECEIPT` on a mismatch. `UNKNOWN_ENTRY` means the id is in no definition of the head index, so copy it again from `diff.json`.

   An error whose name starts with `EXCLUDED_` means the tool may not send that definition (`EXCLUDED_SENSITIVE_CONTENT`: the signature or first doc line holds an address, path or token; `EXCLUDED_PREFIX`: an excluded id prefix). There is no receipt: read the definition and its neighbours yourself and write `excluded` as the receipt token.

   Dart classes come in families (the three cache event families in `core/cache`, the `*ApiException` classes, the `Holding Area` and `Task List` bloc events). A shortlist holds 10 entries and a class and its constructor each take one. For a family of more than four look-alikes, expect twins to fall off the end: ask once more with the distinguishing clause, or read the siblings in the same file.

3. **Read the wiki pages** the shortlist points to (`read_capability`). The page names the capability's canonical entry point and its "don't" rules.

4. **Read source** only for shortlisted candidates and for any call that returned an `uncertain` cause. Rule on source, never on a shortlist line alone.

5. **Rule**, one line per new definition, in the review document, in this exact shape:

   ```text
   RULING <symbol id> :: DUPLICATE | EXTEND <symbol> | DISTINCT <why> :: reuse-receipt: <receipt id>
   ```

   One ruling line per symbol; the id has no spaces or commas. The gate's pattern reads `\S+` for the id and `[0-9A-Za-z_-]+` for the receipt, and it refuses a line that opens with `RULING` and does not match. For a file outside the index write `<file>#<name>` as the id and `unindexed` as the receipt token. Never put free text in the receipt position.

   - `DUPLICATE`: an existing symbol already does this. The diff should call it.
   - `EXTEND <symbol>`: the new code belongs inside that symbol, or should wrap it.
   - `DISTINCT <why>`: you read the candidates' source and name the difference in one clause. A same-name class in another feature is not automatically distinct: `NotificationItem` and `ActiveSession` each exist twice in `lib/`, and the two `AuthError` classes are a name collision, not twins.

   An assertion without a receipt is challenged. Lupin's exit gate (`$LUPIN_ROOT/src/lupin_mcp/reuse_exit_gate.py`) accepts a ruling only when its receipt is one of those logged for that symbol's `fetch_similar` calls.

6. **Run mobile's doc and analyzer checks** on the changed Dart files (lupin's Python linters do not read Dart):

   ```bash
   python3 tool/lint_dart_docs.py --strict --json <changed files under lib/>   # eight doc rules, see src/docs/docstring-standard.md
   ./flutter.sh analyze <changed files>                                       # repo-wide analyze has pre-existing noise
   ```

   Lupin's `prose_judge` is not wired to Dart. Write "prose_judge: not run, Dart" in the review document.

7. **Report or reject.** Save the findings (linters plus any ruling you challenge) as a JSON list and ask lupin's flag:

   ```bash
   cd "$LUPIN_ROOT" && PYTHONPATH=src python -m lupin_mcp.reuse_review_gate --findings findings.json
   ```

   It prints JSON with `mode`, `reject`, `count` and `findings`. With the flag false the mode is `report-only`: list the findings in the review and reject nothing. Exit code 1 means reject. An empty list `[]` answers `report-only`, `count` 0.

## The three vocabularies

| `check_exists` verdict | `plan-review.md` section 4 prior-art label | Reuse-reviewer ruling |
| --- | --- | --- |
| `REUSE` | `reuse-as-is` | `DUPLICATE` |
| `EXTEND` | `extend-existing` | `EXTEND <symbol>` |
| `NEW` | no prior art found | `DISTINCT <why>`, only after reading the shortlist's source; a `NEW` verdict does not rule `DISTINCT` by itself |
| `UNCERTAIN_READ_SOURCE` | none yet: read the source first | rule only after reading the candidates |

## Rules

- Jev builds shortlists and you rule. Every `DUPLICATE` or `DISTINCT` ruling comes from reading source.
- An `uncertain` cause obliges you to read the candidates. The causes are `LOW_CONFIDENCE`, `CALL_FAILED`, `KEY_UNREADABLE`, `DEPENDENCY_MISSING`, `NOT_LUPIN_TREE` and `INDEX_STALE`. Treat it as unknown, never as `NEW`. A mobile call answered `UNCERTAIN_READ_SOURCE` with `LOW_CONFIDENCE` on six of thirteen duplicate-class needs in the 2026.10.20 baseline, so expect it.
- A reuse miss is a symbol that should have been on the shortlist and was not. Baseline misses so far: three `*ApiException` classes (twelve look-alikes, ten slots).
- The id changes when the definition's signature or first doc line changes.
- Cite the id from the call you made on the final head. An id from an earlier edit still replays, but it describes the older text.
- Report a miss to the manager as a task-store row (project `lupin`, title prefix `[LUPIN-MOBILE]`) with the receipt id and the symbol.
- The counter-reviewer replays your receipts with `replay( receipt_id, root )` and reads the source of any candidate you dismissed.
- The baseline (set, scoring script, receipts) is in `/mnt/DATA01/include/www.deepily.ai/projects-data/lupin-mobile/reuse-review/negatives-2026.10.20/`.

## Counter-reviewer brief

This brief is for the second reviewer. The first reviewer's rulings are claims. You re-run the evidence behind each one and read what the first reviewer set aside. You do not rewrite the rulings. You report where a ruling does not hold. Spawn it for every review that cites receipts, `EXTEND` rulings included.

### Inputs

- The review document with its `RULING` lines.
- The head tree the review was written against.
- Nothing from the first reviewer's notes. Read the rulings, not the reasoning around them.

### Procedure

1. **Replay every cited receipt.** For each ruling call `replay( receipt_id, root )` once. A ruling whose receipt token is `excluded` has nothing to replay: read the definition yourself and write `NOTHING_TO_REPLAY`. Read `frozen` and `head` beside `stored`.
   - `frozen` is a re-run against the inputs the receipt recorded. It tests the receipt, not the model.
   - `head` is a re-run against the current tree and index. It tests whether the code or the model still agrees.
   - A difference in `frozen` means the receipt is damaged or was altered. Flag the ruling and stop on that row.
   - A difference in `head` means the answer moved. Note which shortlist entries appeared or left.
   - A named error (`RECEIPT_MISSING`, `RECEIPT_CORRUPT`, `RECEIPT_ID_MISMATCH`, `SNAPSHOT_MISSING`, `SNAPSHOT_CORRUPT`, `CACHE_MISSING`, `CACHE_CORRUPT`) is a finding, not a verdict.

2. **Read the dismissed candidates.** Take each symbol on a receipt's `shortlist` or `nearest` that the ruling does not name. Read its source and its wiki page. For a `DISTINCT` ruling, check the stated reason against what the candidate does. For a `DUPLICATE` ruling, check that the named symbol is the best of the shortlist.

3. **Look for what the receipt missed.** Search `lib/` for the operation the new definition performs, with one or two fixed-string searches. For a family (events, exceptions, bloc events), list the siblings in the same directory: a twin in neither the shortlist nor `nearest` is a miss.

4. **Write one line per ruling** in the counter-review document:

   ```text
   COUNTER <symbol id> :: HOLDS | CHALLENGED <why> | UNVERIFIED <cause> | NOTHING_TO_REPLAY :: reuse-receipt: <id>
   ```

   - `HOLDS`: the replay agrees and no dismissed candidate does the job.
   - `CHALLENGED <why>`: a dismissed candidate, or a head difference, changes the ruling. Name the symbol.
   - `UNVERIFIED <cause>`: a named replay error or an unreadable source stopped the check. Give the error name.
   - `NOTHING_TO_REPLAY`: the ruling cites `excluded`; it is not a failed check.

5. **Log each miss.** A symbol the receipt should have listed is a miss. Report it to the manager as a task-store row (project `lupin`, title prefix `[LUPIN-MOBILE]`) with the receipt id and the symbol. The librarian repairs the wiki from that row.

### Limits

- Replay at `head` makes a model call. Replay the receipts of definitions in dispute first.
- A `HOLDS` line is a statement about the receipt and the candidates you read, not about the tree you did not read.
- The counter-reviewer cites its own receipt only for a call it makes. A ruling it challenges keeps the first reviewer's receipt id.
