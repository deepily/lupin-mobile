import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/auth/domain/auth_bloc.dart';
import 'package:lupin_mobile/features/auth/domain/auth_state.dart';
import 'package:lupin_mobile/features/auth/presentation/auth_gate.dart';

import '../../_harness/test_app.dart';

/// Covers the navigation contract AuthGate owns — specifically, the bug that
/// shipped was: login succeeds → AuthAuthenticated → UI never navigated. A
/// widget test here means a future regression in this contract fails fast at
/// the widget layer, not on an emulator after deploy.
void main() {
  setUpAll( registerHarnessFallbacks );

  group( "AuthGate", () {
    late MockAuthBloc auth;
    late MockServerContextService ctx;

    setUp(() {
      auth = MockAuthBloc();
      ctx  = MockServerContextService();
      stubServerContext( ctx );
    });

    Widget underTest() {
      return MaterialApp(
        home: BlocProvider<AuthBloc>.value(
          value: auth,
          child: AuthGate(
            serverContext      : ctx,
            authenticatedChild : const _SentinelChild(),
          ),
        ),
      );
    }

    testWidgets( "AuthAuthenticated state renders authenticatedChild", ( tester ) async {
      whenListen(
        auth,
        Stream<AuthState>.fromIterable( [
          const AuthAuthenticated(
            userId      : "uid-1",
            email       : "a@b.com",
            accessToken : "acc-1",
          ),
        ] ),
        initialState: const AuthInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      expect( find.byType( _SentinelChild ), findsOneWidget );
      expect( find.text( "AUTH_SENTINEL" ),  findsOneWidget );
    });

    testWidgets( "AuthUnauthenticated state renders LoginScreen (not authenticatedChild)", ( tester ) async {
      whenListen(
        auth,
        Stream<AuthState>.fromIterable( [
          const AuthUnauthenticated( lastEmail: "a@b.com" ),
        ] ),
        initialState: const AuthInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      expect( find.byType( _SentinelChild ), findsNothing );
      // TestKeys.loginEmailField is unique to LoginScreen and survives i18n.
      expect( find.byKey( const Key( TestKeys.loginEmailField ) ), findsOneWidget );
    });

    testWidgets( "AuthInitial + AuthLoading show a progress indicator", ( tester ) async {
      whenListen(
        auth,
        Stream<AuthState>.fromIterable( [
          const AuthLoading(),
        ] ),
        initialState: const AuthInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      expect( find.byType( CircularProgressIndicator ), findsOneWidget );
      expect( find.byType( _SentinelChild ),            findsNothing   );
    });

    // Rick 2026-09-17: a failed sign-in wiped the password. The bloc goes
    // Unauthenticated → Loading → Error; the Loading step used to swap the
    // login form for a spinner and back, rebuilding it empty.
    testWidgets( "a failed login keeps the typed email and password in the form", ( tester ) async {
      final states = StreamController<AuthState>();
      addTearDown( states.close );
      whenListen( auth, states.stream, initialState: const AuthUnauthenticated() );

      await tester.pumpWidget( underTest() );
      await tester.enterText( find.byKey( const Key( TestKeys.loginEmailField    ) ), "u@x.y" );
      await tester.enterText( find.byKey( const Key( TestKeys.loginPasswordField ) ), "hunter2" );

      states.add( const AuthLoading() );
      await tester.pump();
      expect( find.byKey( const Key( TestKeys.loginPasswordField ) ), findsOneWidget,
        reason: "the form stays mounted while the attempt is in flight" );

      states.add( const AuthError( message: "Invalid credentials", lastEmail: "u@x.y" ) );
      await tester.pump();
      await tester.pump();

      String textOf( String key ) =>
        ( tester.widget( find.byKey( Key( key ) ) ) as TextFormField ).controller!.text;
      expect( textOf( TestKeys.loginEmailField    ), "u@x.y" );
      expect( textOf( TestKeys.loginPasswordField ), "hunter2" );
      expect( find.text( "Invalid credentials" ), findsOneWidget, reason: "the error still shows" );
    });

    testWidgets( "startup loading from AuthInitial still shows the spinner, not the form", ( tester ) async {
      final states = StreamController<AuthState>();
      addTearDown( states.close );
      whenListen( auth, states.stream, initialState: const AuthInitial() );

      await tester.pumpWidget( underTest() );
      states.add( const AuthLoading() );
      await tester.pump();

      expect( find.byType( CircularProgressIndicator ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.loginPasswordField ) ), findsNothing );
    });
  });
}

class _SentinelChild extends StatelessWidget {
  const _SentinelChild();
  @override
  Widget build( BuildContext context ) => const Scaffold(
    body: Center( child: Text( "AUTH_SENTINEL" ) ),
  );
}
