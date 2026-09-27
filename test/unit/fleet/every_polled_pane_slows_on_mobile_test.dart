import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/finished_tasks/domain/finished_tasks_bloc.dart';
import 'package:lupin_mobile/features/fleet/domain/pane_polling_mixin.dart';
import 'package:lupin_mobile/features/fleet_status/domain/fleet_status_bloc.dart';
import 'package:lupin_mobile/features/holding_area/domain/holding_area_bloc.dart';
import 'package:lupin_mobile/features/task_list/domain/task_list_bloc.dart';

/// 🔴 THE GUARD ON GAP G8, AND IT IS A CENSUS RATHER THAN A BEHAVIOUR TEST.
///
/// The metered rule — 60 s on Wi-Fi, 180 s on mobile data — was written as a
/// `pollInterval` override in `TaskListBloc` and again, word for word, in
/// `HoldingAreaBloc`. `FleetStatusBloc` mixes in the same mixin and did NOT write it, so
/// it polled every 60 s on the operator's data plan. Nothing failed. Nothing could:
/// every test of the rule was a test of one of the two panes that HAD it.
///
/// ⚠️ THAT IS THE FAILURE SHAPE THIS FILE EXISTS FOR, AND FIXING FLEET STATUS DOES NOT
/// CLOSE IT. A fifth pane that mixes in `PanePollingMixin` tomorrow inherits the rule
/// now — but a fifth pane that overrides `pollInterval` back to a constant, for a
/// reason that seems good at the time, re-opens G8 exactly as it was. So this asserts
/// the PROPERTY over the whole population rather than the fix on the one pane that
/// lacked it.
///
/// 🔴 AND THE CENSUS USED TO BE A COMMENT ASKING A HUMAN TO RUN A GREP, WHICH IS HOW IT
/// CAME TO BE WRONG. The old header said *"`_polledPaneTypes` is the list a reviewer
/// checks against `grep -rl 'PanePollingMixin' lib/`"* and *"keep this list equal to that
/// output"* — and on 2026-09-23 it stopped being equal on the very day it was written.
/// `FinishedTasksBloc` (`finished_tasks_bloc.dart`) mixed the mixin in, in commit
/// `aa2527c`; this census landed in `f2f5ced` the same day, holding three names.
/// `expect( polledPaneTypes, hasLength( 3 ) )` passed green for four days over a
/// population of four. Found by Pocholo 📣 2026-09-27 (B1a) by running the grep the
/// comment names — which is the one thing a comment cannot make anyone do.
///
/// ⚠️ THE EXTRACTION WOULD HAVE MADE IT WORSE, AND SILENTLY. After
/// `PaneVisibilityMixin` landed, the declarations read
/// `with PaneVisibilityMixin<E, S>, PanePollingMixin<E, S>`, so the literal string
/// `'with PanePollingMixin'` matched **nothing**. A reviewer following the old comment
/// would have got **zero** and the `hasLength` assertion would still have passed: a
/// control that goes green when the thing it protects is gone. (Pocholo, B1b.)
///
/// ⇒ **The grep is now the test's own, not a reader's errand.** [_blocsMixingInPolling]
/// scans `lib/` and derives the population; the census below must equal it exactly.
/// Negative control: delete a name from `polledPaneTypes` and this file goes red on the
/// first test, whatever the declaration's line shape.
void main() {
  // The census. It must equal what `_blocsMixingInPolling()` finds in `lib/` — and the
  // first test below is what makes that a check rather than a hope.
  const polledPaneTypes = <Type>[
    TaskListBloc,
    HoldingAreaBloc,
    FleetStatusBloc,
    FinishedTasksBloc,
  ];

  test( "every polled pane is accounted for in this file", () {
    // ⚠️ THE SCAN IS THE AUTHORITY, AND THE CENSUS IS WHAT IS BEING CHECKED — that way
    // round. A pane added to `lib/` and not to the list below fails here, which is the
    // one way this file could previously lie.
    final inSource = _blocsMixingInPolling();
    final inCensus = polledPaneTypes.map( ( t ) => t.toString() ).toSet();

    expect(
      inSource,
      isNotEmpty,
      reason: "the scan found NO bloc mixing in PanePollingMixin. That is not a green "
              "result — it means the pattern in `_blocsMixingInPolling` no longer "
              "matches how the declaration is written, and this whole file has stopped "
              "guarding anything. Fix the pattern, do not shorten the census",
    );
    expect(
      inSource,
      equals( inCensus ),
      reason: "the census disagrees with `lib/`. Add the missing bloc(s) to "
              "`polledPaneTypes` AND to `_sourceFor`, or remove what is gone — do not "
              "edit this assertion. In `lib/` but not the census: "
              "${inSource.difference( inCensus )}. In the census but not `lib/`: "
              "${inCensus.difference( inSource )}",
    );
    expect( polledPaneTypes, hasLength( inSource.length ) );
  } );

  group( "🔴 no pane may override the metered interval back to a constant", () {
    // The mixin's default IS the rule now, so the property to assert is that nobody has
    // taken it back. A pane that overrides `pollInterval` with a literal would be
    // invisible to a test of the mixin alone.
    test( "the mixin's own constants carry both numbers", () {
      // ⚠️ READ OFF THE MIXIN'S CONSTANTS, NOT RE-TYPED AS LITERALS. A test that
      // declares its own `Duration( seconds: 180 )` and compares the two agrees with
      // itself forever; these are the values the timer is actually built from.
      expect( PanePollingMixin.wifiInterval, const Duration( seconds: 60 ) );
      expect( PanePollingMixin.mobileInterval, const Duration( seconds: 180 ) );
      expect(
        PanePollingMixin.mobileInterval - PanePollingMixin.wifiInterval,
        const Duration( seconds: 120 ),
        reason: 'a metered pane polls a third as often, which is the whole rule',
      );
    } );

    for ( final type in polledPaneTypes ) {
      test( "$type does not declare its own pollInterval", () {
        // ⚠️ THIS IS ASSERTED IN THE SOURCE, NOT THE TYPE SYSTEM, BECAUSE DART CANNOT
        // ASK "did this class override that member". Reading the file is the only way
        // to see an override that shadows the shared rule, and an override is exactly
        // what G8 was.
        final path = _sourceFor( type );
        final src  = _read( path );
        expect(
          src.contains( 'Duration get pollInterval' ),
          isFalse,
          reason: "$path declares its own pollInterval. That is how G8 happened: two "
                  "panes had the metered rule, one did not, and the difference was "
                  "invisible. If this pane genuinely needs a different cadence, say so "
                  "here and in the mixin — do not re-copy the rule",
        );
      } );
    }
  } );
}

String _sourceFor( Type type ) => switch ( type.toString() ) {
      'TaskListBloc'      => 'lib/features/task_list/domain/task_list_bloc.dart',
      'HoldingAreaBloc'   => 'lib/features/holding_area/domain/holding_area_bloc.dart',
      'FleetStatusBloc'   => 'lib/features/fleet_status/domain/fleet_status_bloc.dart',
      'FinishedTasksBloc' => 'lib/features/finished_tasks/domain/finished_tasks_bloc.dart',
      _                   => throw StateError( 'no source path recorded for $type' ),
    };

String _read( String path ) => File( path ).readAsStringSync();

/// Every class in `lib/` whose declaration mixes in `PanePollingMixin`, by name.
///
/// ⚠️ COMMENTS ARE STRIPPED FIRST, AND THAT IS NOT TIDINESS. Both mixin headers carry a
/// fenced example reading `class XBloc extends Bloc<E, S> with PaneVisibilityMixin<E, S>,
/// PanePollingMixin<E, S>` — documentation of the required order. A scan over raw text
/// counts `XBloc` as a pane and the census can never match.
///
/// The declaration spans three lines in every real host, so this matches over
/// whitespace-normalised source rather than line by line — the exact brittleness that
/// made the old comment's `grep -rl 'with PanePollingMixin'` return zero after the
/// extraction.
Set<String> _blocsMixingInPolling() {
  final found = <String>{};

  // `[^{;]` cannot cross into a class body or past a declaration's end, so a match is
  // confined to one `class … { ` header. Generic arguments contain neither character.
  final declaration = RegExp(
    r'\bclass\s+(\w+)\b[^{;]*?\bwith\b[^{;]*?\bPanePollingMixin\b[^{;]*?\{',
    dotAll: true,
  );

  for ( final file in Directory( 'lib' ).listSync( recursive: true ).whereType<File>() ) {
    if ( !file.path.endsWith( '.dart' ) ) continue;

    final src = _stripComments( file.readAsStringSync() );
    for ( final m in declaration.allMatches( src ) ) {
      found.add( m.group( 1 )! );
    }
  }
  return found;
}

/// Strip `//`-to-end-of-line and `/* … */` comments. Deliberately simple: it does not
/// understand string literals, which is safe here because no string in `lib/` contains a
/// class declaration that mixes in the polling mixin.
String _stripComments( String src ) => src
    .replaceAll( RegExp( r'/\*.*?\*/', dotAll: true ), '' )
    .replaceAll( RegExp( r'//[^\n]*' ), '' );
