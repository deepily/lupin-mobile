import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_bloc.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_event.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_state.dart';
import 'package:lupin_mobile/features/focus_mode/presentation/focus_chat_pane.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/services/notification_filter/notification_stop_list.dart';

class _MockFocusBloc extends MockBloc<FocusChatEvent, FocusChatState> implements FocusChatBloc {}

/// Long enough to wrap at any width, so the bubble grows to its cap.
final _long = List.filled( 60, 'word' ).join( ' ' );

NotificationItem _item( String id, { String type = 'task' } ) => NotificationItem(
  id: id, message: _long, type: type, priority: 'low', senderId: 'S',
  timestamp: DateTime( 2026, 9, 16, 18 ), played: true, playCount: 0,
  responseRequested: false, suppressDing: true, displayQualifierWidget: false,
);

/// Row 3681bd9e — bubbles use 90% of the pane, whatever the screen is. A
/// fixed 320 px cap left them at about half the width of an unfolded Pixel
/// Fold while the header spanned it all.
void main() {
  late _MockFocusBloc        bloc;
  late NotificationStopList  sl;

  setUp( () async {
    SharedPreferences.setMockInitialValues( {} );
    sl   = NotificationStopList( await SharedPreferences.getInstance() );
    bloc = _MockFocusBloc();
    final st = const FocusChatState.initial().copyWith(
      senderOrder: const [ 'S' ], focusedSender: 'S', hydration: FocusHydration.ready,
      windows: { 'S': [
        FocusMessage( item: _item( 'in' ) ),
        FocusMessage( item: _item( 'out', type: 'user_initiated_message' ), answered: true ),
      ] } );
    whenListen( bloc, Stream<FocusChatState>.fromIterable( [ st ] ), initialState: st );
  } );

  Future<( double pane, double inbound, double reply )> widthsAt( WidgetTester tester, Size screen ) async {
    tester.view.physicalSize     = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown( tester.view.reset );
    await tester.pumpWidget( MaterialApp( home: Scaffold( body: BlocProvider<FocusChatBloc>.value(
      value: bloc, child: FocusChatPane( userEmail: 'rick@test.com', stopList: sl ) ) ) ) );
    await tester.pump();
    final pane    = tester.getSize( find.byKey( const Key( TestKeys.focusChatPane ) ) ).width;
    final inbound = tester.getSize( find.byKey( const Key( '${TestKeys.focusBubblePrefix}in' ) ) ).width;
    final reply   = tester.getSize( find.byKey( const Key( '${TestKeys.focusBubblePrefix}out' ) ) ).width;
    return ( pane, inbound, reply );
  }

  test( 'the fraction is 90%', () {
    expect( FocusChatPane.bubbleWidthFraction, 0.9 );
  } );

  testWidgets( 'an unfolded Fold: both directions grow well past the old 320 px cap', ( tester ) async {
    final ( pane, inbound, reply ) = await widthsAt( tester, const Size( 1080, 1000 ) );
    expect( inbound, greaterThan( 320 ), reason: 'the old fixed cap' );
    expect( reply,   greaterThan( 320 ) );
    expect( inbound, lessThanOrEqualTo( pane * 0.9 + 0.5 ) );
    expect( inbound, greaterThan( pane * 0.8 ), reason: 'a wrapping message fills most of its 90% cap' );
    expect( reply,   greaterThan( pane * 0.8 ) );
  } );

  testWidgets( 'a narrow phone: still 90%, not a fixed width', ( tester ) async {
    final ( pane, inbound, _ ) = await widthsAt( tester, const Size( 400, 800 ) );
    expect( inbound, lessThanOrEqualTo( pane * 0.9 + 0.5 ) );
    expect( inbound, greaterThan( pane * 0.8 ) );
  } );
}
