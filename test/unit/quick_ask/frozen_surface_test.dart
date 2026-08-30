/// AC-S4.10a — the blast-radius pin on the shared focus-mode surface, AS A
/// TEST rather than a command somebody remembers to run.
///
/// The rule: S4 changes `prompt_bodies.dart` and `focus_chat_pane.dart`, which
/// focus mode has been using all along. The existing focus-mode prompt and
/// notification tests must therefore run against the changed surface and stay
/// green WITHOUT being edited, re-baselined or quarantined. An S4 commit that
/// edits one of them to make it pass has moved the goalposts, and this goes
/// red instead of passing quietly.
///
/// 🔴 THE EXISTENCE GATE RUNS FIRST, AND IT IS NOT DECORATION.
/// `git diff --exit-code <sha> -- <a path that does not exist>` returns **0**.
/// Measured at `9a9c10c`: two of the five originally-frozen files were not in
/// the tree, so half this pin held nothing on the widest-blast-radius surface
/// in the plan — and reported green. A vacuous pass is worse than no pin,
/// because it is indistinguishable from a real one.
///
/// 🔴 AND THE INSTRUMENT IS CHECKED TOO. A `git diff` that cannot fail — wrong
/// working directory, unresolvable sha, `git` not on PATH — returns green for
/// every possible tree. So this file also diffs a path S4 is KNOWN to have
/// changed and requires that to come back dirty. If the control cannot show a
/// red it is not a control.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The revision S4 started from. The pin is a diff against THIS, not against
/// HEAD — otherwise re-baselining a frozen file inside S4 would pass.
const preS4Sha = '026ffd3';

/// 🔴 A CLOSED LIST, and every entry must exist.
///
/// `interactive_prompt_sheet_test.dart` was REMOVED from this list on
/// 2026-08-29: it is a pinned DELTA under AC-S4.10b now, not a frozen file.
/// `focus_chat_pane_test.dart` and `focus_chat_state_test.dart` were also once
/// named here and are not in the tree at all — that is the defect above.
const frozenFiles = <String>[
  'test/widget/focus_mode/focus_chat_pane_collapse_test.dart',
  'test/unit/focus_mode/focus_chat_bloc_test.dart',
  'test/unit/notifications/notification_bloc_test.dart',
];

/// A file S4 unambiguously DID change. Diffing it is how this test proves the
/// diff can come back dirty at all.
const knownChangedFile = 'lib/features/quick_ask/domain/quick_ask_bloc.dart';

ProcessResult _git( List<String> args ) => Process.runSync( 'git', args );

void main() {
  group( 'AC-S4.10a — the frozen focus-mode surface', () {

    test( 'the git working directory and the pre-S4 revision both RESOLVE', () {
      // Without this, every assertion below degrades to "git errored, so
      // nothing differed" — a green earned by the check being broken.
      final root = _git( [ 'rev-parse', '--show-toplevel' ] );
      expect( root.exitCode, 0,
          reason: 'not inside a git work tree — the pin cannot run: ${root.stderr}' );

      final sha = _git( [ 'rev-parse', '--verify', '$preS4Sha^{commit}' ] );
      expect( sha.exitCode, 0,
          reason: 'pre-S4 revision $preS4Sha does not resolve; the diff would '
                  'compare against nothing: ${sha.stderr}' );
    } );

    test( 'EVERY frozen path EXISTS — checked BEFORE any diff', () {
      // First, because `git diff --exit-code` on an absent path returns 0 and
      // the whole pin evaporates without a word.
      for ( final f in frozenFiles ) {
        expect( File( f ).existsSync(), isTrue,
            reason: 'FROZEN PATH ABSENT: $f — this pin is vacuous. Either the '
                    'file moved and the list is stale, or the name is a typo. '
                    'Fix the list; do NOT delete the entry.' );
      }
      expect( frozenFiles, isNotEmpty,
          reason: 'an empty frozen list passes every check ever written' );
    } );

    test( 'the diff can actually come back DIRTY — the instrument works', () {
      expect( File( knownChangedFile ).existsSync(), isTrue );
      final r = _git( [ 'diff', '--exit-code', preS4Sha, '--', knownChangedFile ] );
      expect( r.exitCode, isNot( 0 ),
          reason: '$knownChangedFile shows NO change since $preS4Sha. S4 '
                  'certainly changed it, so this diff is inert — wrong '
                  'directory, wrong sha, or the wrong file — and every green '
                  'below is meaningless.' );
    } );

    test( 'no frozen file has been edited since the pre-S4 revision', () {
      for ( final f in frozenFiles ) {
        final r = _git( [ 'diff', '--exit-code', preS4Sha, '--', f ] );
        expect( r.exitCode, 0,
            reason: 'AC-S4.10a VIOLATED — $f changed since $preS4Sha.\n'
                    'A frozen test that had to be edited to stay green is a '
                    'regression wearing a re-baseline.\n${r.stdout}' );
      }
    } );
  } );
}
