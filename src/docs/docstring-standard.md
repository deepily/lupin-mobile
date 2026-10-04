# Dart doc-comment standard

Status: approved by Rick on 2026-09-30 (D10; record `R5b-M1` in `src/docs/decisions/README.md`). Applies to every `///` block and `//` comment in `lib/`. It adapts the eight rules of the lupin documentation rewrite plan to Effective Dart and `flutter_lints`.

## Block shape

```dart
/// One sentence saying what this does or decides, at most 90 characters.
///
/// Up to four lines of why: the constraint and its consequence.
/// Design: src/docs/decisions/README.md
///
/// Requires:
///   - only where a precondition is not obvious from the signature
///
/// Ensures:
///   - only where behaviour is not obvious from the name and types
```

- The summary is one sentence on one line, followed by a blank `///` line. The symbol index reads only that line.
- The why section is optional and never longer than four lines.
- `Design:` names a path that exists in this repo, with an anchor if needed. Omit the line when no design document or decision record exists.
- To name one decision record, add its ID in parentheses after the path: `Design: src/docs/decisions/README.md (R-HA-accordion)`. This works for word-form IDs only. The doc linter reads an ID such as `R1=B` or `AC-S1.10` as a bare reference, so cite those records by path alone, and give every new record a word-form ID.
- Write Dart doc references as `[Name]` only for symbols that resolve.

## The eight rules, in Dart

1. **Lead with the claim.** The first line states what the member does, in 90 characters or fewer.
2. **Say only what the signature does not.** Don't restate the name or the types. Effective Dart: don't write a comment that repeats what the code already says.
3. **One idea per sentence**, under 25 words.
4. **No typographic emphasis.** No all-caps words, no emoji or symbols such as ⚠️ 🔴 ⇒, no bold or italics for emphasis. Acronyms and code identifiers are fine.
5. **No rhetoric.** No aphorisms, no "not X but Y" setups, and none of: deliberately, by construction, load-bearing, the point. State the constraint and its consequence.
6. **Every reference resolves.** Use a file path or a `[Symbol]`. Don't cite a section number, row id, ruling label or acceptance-criterion id without a path that explains it.
7. **Current state only.** No dates, no "used to", no quoted conversations. A ruling becomes a one-line record in `src/docs/decisions/`, and the code links to it. Other history goes to the `Design:` document, or else the commit message.
8. **Fit the template.** A member doc follows the block shape above. A reference page is at most 1,500 words.

## When Requires and Ensures are required

Contracts are required only where behaviour is not obvious (D8). A contract is needed when a member:

- orders, filters, groups or de-duplicates its input in a way the name does not say;
- returns a value for a failure case instead of throwing, or throws on a case the caller might not expect;
- has a precondition the types do not enforce (non-empty list, called once, called on the UI isolate);
- has a side effect outside its own object (timers, streams, persisted state, network).

A getter, a trivial constructor, a field, a pass-through method or a plain enum value needs only its summary. Omit `Requires:` when the answer is "nothing". Each clause states one checkable fact.

## By construct

| Construct | What to write |
| --- | --- |
| Widget | Summary of what the user sees or does. Document constructor parameters only when a value is non-obvious (units, null meaning). |
| `State` class | Usually private, so a `//` comment is enough. Document the `State` only if it owns a timer, stream or controller that must be disposed. |
| Bloc, provider, service | Summary of the responsibility. State its lifetime (route-scoped or app-wide) and what it listens to or polls. Document each public event or method that changes state. |
| Model (Equatable or freezed-style) | Summary of what one instance represents. Document a field only when its unit, null meaning or source is not obvious. `props` and `copyWith` need nothing. |
| Enum | Summary of what the enum classifies. Document each value whose meaning is not its name. |
| Extension | Summary of the type it extends and why. Each public member gets a summary. |
| Constructor | Skip when it only assigns fields. Document factory and named constructors by what they build. |
| Constant | One line giving its meaning and unit. |

Mobile uses Bloc and Equatable; no file in `lib/` uses `@freezed` today, so the model rule applies to Equatable classes.

## Ignores

`// ignore: public_member_api_docs` is allowed only with a reason on the same line: `// ignore: public_member_api_docs - generated override, see x.dart`. A reason names a fact (generated code, override of a documented member, platform callback), not a wish ("TODO", "obvious", "later"). `ignore_for_file` for this rule is never allowed. The coverage bar is zero `public_member_api_docs` hits per swept directory (D8).

## Strict directories

Every gated directory in `tool/data/gated_dirs.txt` is strict unless `tool/data/strict_exempt.txt` names it. In a strict directory ANY analyzer finding (error, warning, style note) blocks the commit (`dart analyze --fatal-infos`), every `analysis_options.yaml` that applies (the root one, the directory's own, any nested one) must be the plain template (`include:` of the root file, then `public_member_api_docs: true`; the root file as committed), so no rule can be switched off, no severity lowered and no path excluded, and an `// ignore:` comment needs a reason after ` - ` (`ignore_for_file` is refused). An exempt directory keeps the docs-only check. Each exempt line carries a reason and a row; delete the line when the directory analyzes clean. A new gated directory is strict from its first commit.

## Examples from lib/

Excerpts are trimmed with `…`. Before-blocks are copied from the tree at `cf5be6f`.

### 1. `groupByFiler`, `lib/features/holding_area/data/holding_area_models.dart`

Before (excerpt, 42 lines in all):

```dart
/// Group held rows by the PERSONA who filed them.
///
/// 🔴 THE GROUPING KEY IS THE PERSONA, SESSION HASH STRIPPED — RICK'S RULING R1=B,
/// 2026-09-22, AND IT REVERSES WHAT THIS FUNCTION USED TO DO. …
/// > *"Stripping the hash to group by bare persona would merge one persona's sessions …"*
/// ⚠️ EVERY WORD OF THAT IS STILL TRUE. …
/// ⇒ SO THE WIDER BLAST RADIUS IS HANDLED RATHER THAN AVOIDED, …
```

After:

```dart
/// Groups held rows by the persona that filed them, one group per persona.
///
/// The key is the persona with the session hash stripped, in display case, so
/// "Krishna" and "krishna" share a group. Do not derive it with
/// `split( " " ).first`: a persona can have two words (`lib/core/text/persona_label.dart`).
/// Design: src/docs/decisions/README.md
///
/// Ensures:
///   - groups are ordered by persona name, ignoring case
///   - a row with no filer goes in one trailing "Unattributed" group, never dropped
///   - row order within a group is the server's order
```

The wide-blast-radius point survives in the decision record, and `FilerGroup.count` documents that ids and count come from the same rows.

### 2. `JobStatus`, `lib/shared/models/job.dart`

Before (excerpt): `/// DISPOSITION (AC-S1.10, 2026-08-29): **LEFT ALONE — not superseded by [JobLane], and not quarantined.**` followed by 19 lines.

After:

```dart
/// Lifecycle state of a locally stored [Job]; never sent over the wire.
///
/// [JobLane] is the wire vocabulary and is not replaced by this enum. They
/// disagree on two of four members (`running`/`completed` here, `run`/`done`
/// there), and nothing maps between them. If a mapping is needed, write one named
/// adapter; do not assume the names match.
/// Design: src/rnd/2026.06.11-focus-mode-voice-chat/10-section-s1-tts-pause-resume.md
enum JobStatus {
```

Dependency: `test/unit/queue/lane_vocabulary_test.dart` (line 64) reads this block and asserts it contains `AC-S1.10` and one of `superseded`, `LEFT ALONE`, `left alone` or `quarantined`. The rewrite keeps "not replaced" but drops both asserted phrases, so the test goes red. The M0 census must give that test a disposition (keep-and-update, convert-to-behaviour or retire) before this block changes.

### 3. `holdingWontFixAllHint`, same file

Before:

```dart
/// 🔴 THE REASON IS PER GROUP, NOT PER ROW, AND THIS SAYS SO. …
/// … deliberately the blunt instrument and is labelled as such.
```

After:

```dart
/// Accessibility hint for the won't-fix-all button of one filer's group.
///
/// One reason is applied to every row in the group, so the hint says so and
/// points to the per-row control for rows that need different reasons.
```

### 4. `HoldingAreaBloc`, `lib/features/holding_area/domain/holding_area_bloc.dart`

Before: `/// ⚠️ ROUTE-SCOPED, NOT AN APP-ROOT SINGLETON, for the reason the Task List's bloc records: …`

After:

```dart
/// State and events for the Holding Area pane.
///
/// Register it per route, not at the app root: a root-level bloc outlives its
/// route and its poll timer then runs against whichever screen is showing. See
/// [PanePollingMixin].
```

### 5. A missing doc, `QuickSettingsPresetExtension`, `lib/core/settings/settings_service.dart`

Before: no doc comment on the extension. After:

```dart
/// Display names for [QuickSettingsPreset].
extension QuickSettingsPresetExtension on QuickSettingsPreset {
```

Most of the work in `lib/core`, `lib/services` and `lib/shared` is this kind: a summary that was never written.

## Tests that read doc text

A test that asserts a phrase inside a `///` block means the test fails when that block's wording changes. The census in M0 lists these tests and gives each one disposition: keep-and-update, convert-to-behaviour, or retire with a reason. No sweep touches such a block before its test has a disposition.
