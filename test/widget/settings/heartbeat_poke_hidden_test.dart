/// The stop poke switch is hidden on the Notifications screen.
///
/// Hidden, not deleted: the section still works when mounted directly, and one constant
/// shows it again.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/settings/data/heartbeat_poke_repository.dart';
import 'package:lupin_mobile/features/settings/presentation/heartbeat_poke_section.dart';
import 'package:lupin_mobile/features/settings/presentation/notification_management_screen.dart';
import 'package:lupin_mobile/services/notification_audio/notification_preferences.dart';

class _Poke implements HeartbeatPokeRepository {
  int reads = 0;
  @override
  Future<HeartbeatPokeState> getState() async {
    reads++;
    return const HeartbeatPokeState( muted: false );
  }
  @override
  Future<HeartbeatPokeState> setMuted( bool muted ) async =>
      HeartbeatPokeState( muted: muted );
}

void main() {
  testWidgets( "the screen does not show the poke switch, and does not read the poke route",
      ( tester ) async {
    SharedPreferences.setMockInitialValues( {} );
    final prefs = NotificationPreferences( await SharedPreferences.getInstance() );
    final poke  = _Poke();

    await tester.pumpWidget( MaterialApp(
      home: NotificationManagementScreen( prefs: prefs, heartbeatPoke: poke ),
    ) );
    await tester.pumpAndSettle();

    expect( find.byType( HeartbeatPokeSection ), findsNothing );
    expect( find.byKey( const Key( TestKeys.heartbeatPokeSwitch ) ), findsNothing );
    expect( poke.reads, 0 );
    // The screen itself is intact.
    expect( find.byKey( const Key( TestKeys.notifMgmtMaster ) ), findsOneWidget );
  } );

  test( "one constant shows it again", () {
    expect( kShowHeartbeatPokeSwitch, isFalse );
  } );
}
