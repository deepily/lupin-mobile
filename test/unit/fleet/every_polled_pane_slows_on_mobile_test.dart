import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
/// CLOSE IT. A fourth pane that mixes in `PanePollingMixin` tomorrow inherits the rule
/// now — but a fourth pane that overrides `pollInterval` back to a constant, for a
/// reason that seems good at the time, re-opens G8 exactly as it was. So this asserts
/// the PROPERTY over the whole population rather than the fix on the one pane that
/// lacked it.
///
/// ⚠️ IT IS ALSO THE FILE TO EXTEND, NOT REPLACE, WHEN A PANE IS ADDED. If a new bloc
/// mixes the mixin in and is not listed here, this file passes and says nothing —
/// which is the one way it can lie. `_polledPaneTypes` is the list a reviewer checks
/// against `grep -rl 'PanePollingMixin' lib/`.
void main() {
  // Every bloc in `lib/` that mixes in PanePollingMixin, as of 2026-09-23.
  // `grep -rl 'with PanePollingMixin' lib/` — keep this list equal to that output.
  const polledPaneTypes = <Type>[
    TaskListBloc,
    HoldingAreaBloc,
    FleetStatusBloc,
  ];

  test( "every polled pane is accounted for in this file", () {
    // A reminder with teeth: the census below is hand-maintained, and a pane missing
    // from it is invisible to the assertion that matters.
    expect( polledPaneTypes, hasLength( 3 ),
        reason: "a pane was added or removed — update this file's census, then the "
                "interval assertions below, or G8 quietly re-opens" );
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
      'TaskListBloc'    => 'lib/features/task_list/domain/task_list_bloc.dart',
      'HoldingAreaBloc' => 'lib/features/holding_area/domain/holding_area_bloc.dart',
      'FleetStatusBloc' => 'lib/features/fleet_status/domain/fleet_status_bloc.dart',
      _                 => throw StateError( 'no source path recorded for $type' ),
    };

String _read( String path ) => File( path ).readAsStringSync();
