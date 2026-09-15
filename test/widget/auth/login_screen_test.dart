import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/core/constants/app_constants.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/services/auth/server_context_service.dart';
import 'package:lupin_mobile/features/auth/domain/auth_event.dart';
import 'package:lupin_mobile/features/auth/domain/auth_state.dart';
import 'package:lupin_mobile/features/auth/presentation/login_screen.dart';

import '../../_harness/test_app.dart';

void main() {
  setUpAll( registerHarnessFallbacks );

  group( "LoginScreen", () {
    late MockAuthBloc auth;
    late MockServerContextService ctx;

    setUp(() {
      auth = MockAuthBloc();
      ctx  = MockServerContextService();
      when( () => auth.state ).thenReturn( const AuthUnauthenticated() );
      stubServerContext( ctx );
    });

    Widget underTest() => testApp(
      authBloc: auth,
      child: LoginScreen( serverContext: ctx ),
    );

    testWidgets( "renders email, password, and submit by TestKeys", ( tester ) async {
      await tester.pumpWidget( underTest() );
      expect( find.byKey( const Key( TestKeys.loginEmailField    ) ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.loginPasswordField ) ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.loginSubmitButton  ) ), findsOneWidget );
    });

    testWidgets( "empty-email submit surfaces validation error", ( tester ) async {
      await tester.pumpWidget( underTest() );
      await tester.tap( find.byKey( const Key( TestKeys.loginSubmitButton ) ) );
      await tester.pump();
      expect( find.text( "Enter a valid email" ), findsOneWidget );
      expect( find.text( "Password required" ),   findsOneWidget );
      verifyNever( () => auth.add( any() ) );
    });

    testWidgets( "valid submit dispatches AuthLoginRequested", ( tester ) async {
      await tester.pumpWidget( underTest() );
      await tester.enterText( find.byKey( const Key( TestKeys.loginEmailField    ) ), "u@x.y" );
      await tester.enterText( find.byKey( const Key( TestKeys.loginPasswordField ) ), "hunter2" );
      await tester.tap( find.byKey( const Key( TestKeys.loginSubmitButton ) ) );
      await tester.pump();
      verify( () => auth.add(
        const AuthLoginRequested( email: "u@x.y", password: "hunter2" ),
      ) ).called( 1 );
    });

    testWidgets( "keyboard enter/done in the password field submits (no Sign-in tap needed)", ( tester ) async {
      await tester.pumpWidget( underTest() );
      await tester.enterText( find.byKey( const Key( TestKeys.loginEmailField    ) ), "u@x.y" );
      await tester.enterText( find.byKey( const Key( TestKeys.loginPasswordField ) ), "hunter2" );
      await tester.testTextInput.receiveAction( TextInputAction.done );
      await tester.pump();
      verify( () => auth.add(
        const AuthLoginRequested( email: "u@x.y", password: "hunter2" ),
      ) ).called( 1 );
      final pw = tester.widget<EditableText>( find.descendant(
          of: find.byKey( const Key( TestKeys.loginPasswordField ) ), matching: find.byType( EditableText ) ) );
      expect( pw.textInputAction, TextInputAction.done );   // the key reads "done", not "return"
    } );

    testWidgets( "enter in the password field with an invalid email does NOT dispatch (validator still gates)", ( tester ) async {
      await tester.pumpWidget( underTest() );
      await tester.enterText( find.byKey( const Key( TestKeys.loginPasswordField ) ), "hunter2" );
      await tester.testTextInput.receiveAction( TextInputAction.done );
      await tester.pump();
      verifyNever( () => auth.add( any() ) );
      expect( find.text( "Enter a valid email" ), findsOneWidget );
    } );

    testWidgets( "initialEmail + initialPassword pre-fill fields and submit sends them", ( tester ) async {
      await tester.pumpWidget( testApp(
        authBloc: auth,
        child: LoginScreen(
          initialEmail    : "dev@x.y",
          initialPassword : "dev-pw",
          serverContext   : ctx,
        ),
      ) );
      expect(
        ( tester.widget( find.byKey( const Key( TestKeys.loginEmailField    ) ) ) as TextFormField )
          .controller?.text,
        "dev@x.y",
      );
      expect(
        ( tester.widget( find.byKey( const Key( TestKeys.loginPasswordField ) ) ) as TextFormField )
          .controller?.text,
        "dev-pw",
      );
      await tester.tap( find.byKey( const Key( TestKeys.loginSubmitButton ) ) );
      await tester.pump();
      verify( () => auth.add(
        const AuthLoginRequested( email: "dev@x.y", password: "dev-pw" ),
      ) ).called( 1 );
    });
  });

  // The server switch on the login screen, driven by the REAL service and
  // the SHIPPED server-contexts.json, at phone width.
  group( "LoginScreen server switch", () {
    late MockAuthBloc auth;
    final shippedJson = File( "assets/config/server-contexts.json" ).readAsStringSync();

    setUp(() {
      auth = MockAuthBloc();
      when( () => auth.state ).thenReturn( const AuthUnauthenticated() );
      SharedPreferences.setMockInitialValues( {} );
    });

    Future<( ServerContextService, SharedPreferences )> pumpReal( WidgetTester tester ) async {
      tester.binding.defaultBinaryMessenger.setMockMessageHandler( "flutter/assets", ( message ) async {
        final key = const StringCodec().decodeMessage( message );
        return key == "assets/config/server-contexts.json"
          ? const StringCodec().encodeMessage( shippedJson )
          : null;
      } );
      tester.view.physicalSize     = const Size( 360, 690 );
      tester.view.devicePixelRatio = 1.0;
      addTearDown( tester.view.reset );

      final ( svc, prefs ) = await tester.runAsync( () async {
        final prefs = await SharedPreferences.getInstance();
        return ( await ServerContextService.load( prefs ), prefs );
      } ) as ( ServerContextService, SharedPreferences );
      await tester.pumpWidget( testApp( authBloc: auth, child: LoginScreen( serverContext: svc ) ) );
      return ( svc, prefs );
    }

    Finder segment( String id ) => find.byKey( Key( "${TestKeys.serverContextSegmentPrefix}$id" ) );

    testWidgets( "offers every context, LAN DEV and LAN TEST included, with DEV selected", ( tester ) async {
      await pumpReal( tester );

      expect( find.byKey( const Key( TestKeys.serverContextToggle ) ), findsOneWidget );
      for ( final id in [ "dev", "test", "lan-dev", "lan-test" ] ) {
        expect( segment( id ), findsOneWidget, reason: "segment $id" );
      }
      final toggle = tester.widget<SegmentedButton<String>>(
        find.byKey( const Key( TestKeys.serverContextToggle ) ) );
      expect( toggle.selected, { "dev" } );
      expect( find.text( "DEV · http://10.0.2.2:7999" ), findsOneWidget );
      expect( tester.takeException(), isNull, reason: "four segments fit at 360 px" );
    } );

    testWidgets( "tapping LAN DEV and confirming switches the server, persists it, and updates the badge", ( tester ) async {
      final ( svc, prefs ) = await pumpReal( tester );

      await tester.tap( segment( "lan-dev" ) );
      await tester.pumpAndSettle();
      expect( find.text( "Switch server?" ), findsOneWidget );
      await tester.tap( find.widgetWithText( FilledButton, "Switch" ) );
      await tester.pumpAndSettle();

      expect( svc.active, "lan-dev" );
      expect( AppConstants.apiBaseUrl, "http://192.168.1.21:7999" );
      expect( AppConstants.wsBaseUrl,  "ws://192.168.1.21:7999" );
      expect( prefs.getString( "active_server_context" ), "lan-dev" );
      expect( find.text( "LAN DEV · http://192.168.1.21:7999" ), findsOneWidget );
      // AppBar badge now reads LAN DEV too (badge + segment + subtitle text).
      expect( find.descendant( of: find.byType( AppBar ), matching: find.text( "LAN DEV" ) ), findsOneWidget );
      verify( () => auth.add( const AuthLogoutRequested() ) ).called( 1 );
      verify( () => auth.add( const AuthServerContextChanged() ) ).called( 1 );
    } );

    testWidgets( "cancelling the dialog leaves the server on DEV", ( tester ) async {
      final ( svc, prefs ) = await pumpReal( tester );

      await tester.tap( segment( "lan-dev" ) );
      await tester.pumpAndSettle();
      await tester.tap( find.widgetWithText( TextButton, "Cancel" ) );
      await tester.pumpAndSettle();

      expect( svc.active, "dev" );
      expect( prefs.getString( "active_server_context" ), isNull );
      verifyNever( () => auth.add( any() ) );
    } );
  } );
}
