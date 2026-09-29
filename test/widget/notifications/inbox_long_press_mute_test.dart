/// Row f1e80e67 (plan §7.5) — long-press an Inbox sender row to mute it.
library;

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/core/di/service_locator.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_bloc.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_state.dart';
import 'package:lupin_mobile/features/notifications/presentation/inbox_screen.dart';
import 'package:lupin_mobile/services/notification_audio/notification_preferences.dart';

import '../../_harness/test_app.dart';

const String _sender = 'claude.code@lookml.deepily.ai#a1b2c3d4';

void main() {
  setUpAll( registerHarnessFallbacks );

  late MockNotificationBloc    bloc;
  late NotificationPreferences prefs;

  setUp( () async {
    SharedPreferences.setMockInitialValues( {} );
    prefs = NotificationPreferences( await SharedPreferences.getInstance() );
    if ( ServiceLocator.isRegistered<NotificationPreferences>() ) {
      ServiceLocator.instance.unregister<NotificationPreferences>();
    }
    ServiceLocator.instance.registerSingleton<NotificationPreferences>( prefs );
    bloc = MockNotificationBloc();
    whenListen( bloc, Stream<NotificationState>.empty(), initialState: NotificationsInboxLoaded(
      senders   : [ SenderSummary( senderId: _sender, lastActivity: DateTime( 2026, 9, 29 ), count: 1 ) ],
      userEmail : "u@x.y",
    ) );
  } );

  tearDown( () {
    if ( ServiceLocator.isRegistered<NotificationPreferences>() ) {
      ServiceLocator.instance.unregister<NotificationPreferences>();
    }
  } );

  testWidgets( 'long-press on a sender row mutes its project; Undo reverses', ( tester ) async {
    await tester.pumpWidget( testApp(
      authBloc: MockAuthBloc(),
      extraProviders: [ BlocProvider<NotificationBloc>.value( value: bloc ) ],
      child: const InboxScreen( userEmail: "u@x.y" ),
    ) );
    await tester.pump();

    await tester.longPress( find.byKey( const Key( '${TestKeys.inboxSenderTilePrefix}$_sender' ) ) );
    await tester.pumpAndSettle();
    expect( find.text( 'Mute lookml' ), findsOneWidget );
    await tester.tap( find.byKey( const Key( TestKeys.senderMuteAction ) ) );
    await tester.pumpAndSettle();
    expect( prefs.isSenderMuted( 'project:lookml' ), isTrue );

    await tester.tap( find.byKey( const Key( TestKeys.senderMuteUndo ) ) );
    await tester.pumpAndSettle();
    expect( prefs.isSenderMuted( 'project:lookml' ), isFalse );
  } );
}
