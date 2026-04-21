import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/features/auth/domain/auth_bloc.dart';
import 'package:lupin_mobile/features/auth/domain/auth_state.dart';
import 'package:lupin_mobile/features/auth/presentation/ws_lifecycle_listener.dart';

import '../../_harness/test_app.dart';

/// Covers the state-transition matrix documented in
/// `src/rnd/v0.1.7/2026.04.19-ws-lifecycle-auth-wiring-plan.md`. The actual
/// WebSocket service is NOT exercised here — callbacks are the seam. These
/// tests verify the seam fires the right hook under the right transitions.
void main() {
  setUpAll( registerHarnessFallbacks );

  group( "WsLifecycleListener", () {
    late MockAuthBloc auth;
    late _FakeHooks   hooks;

    setUp(() {
      auth  = MockAuthBloc();
      hooks = _FakeHooks();
    });

    Widget underTest() {
      return MaterialApp(
        home: BlocProvider<AuthBloc>.value(
          value: auth,
          child: WsLifecycleListener(
            onAuthenticated: hooks.onAuthenticated,
            onSignedOut    : hooks.onSignedOut,
            child          : const _Sentinel(),
          ),
        ),
      );
    }

    testWidgets( "AuthLoading → AuthAuthenticated calls onAuthenticated(userId)", ( tester ) async {
      whenListen(
        auth,
        Stream<AuthState>.fromIterable( [
          const AuthLoading(),
          const AuthAuthenticated(
            userId      : "u-1",
            email       : "a@b.com",
            accessToken : "acc-1",
          ),
        ] ),
        initialState: const AuthInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pumpAndSettle();

      expect( hooks.authenticatedCalls, [ "u-1" ] );
      expect( hooks.signOutCalls,       0 );
    });

    testWidgets( "AuthAuthenticated → AuthAuthenticated (same type) does not refire", ( tester ) async {
      // listenWhen filters on runtime-type change; successive Authenticated
      // emissions (e.g. token refresh) must not trigger redundant connects.
      whenListen(
        auth,
        Stream<AuthState>.fromIterable( [
          const AuthAuthenticated(
            userId      : "u-1",
            email       : "a@b.com",
            accessToken : "acc-1",
          ),
          const AuthAuthenticated(
            userId      : "u-1",
            email       : "a@b.com",
            accessToken : "acc-2", // refreshed token
          ),
        ] ),
        initialState: const AuthInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pumpAndSettle();

      expect( hooks.authenticatedCalls, [ "u-1" ] ); // once, not twice
      expect( hooks.signOutCalls,       0 );
    });

    testWidgets( "AuthAuthenticated → AuthUnauthenticated calls onSignedOut", ( tester ) async {
      whenListen(
        auth,
        Stream<AuthState>.fromIterable( [
          const AuthAuthenticated(
            userId      : "u-1",
            email       : "a@b.com",
            accessToken : "acc-1",
          ),
          const AuthUnauthenticated( lastEmail: "a@b.com" ),
        ] ),
        initialState: const AuthInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pumpAndSettle();

      expect( hooks.authenticatedCalls, [ "u-1" ] );
      expect( hooks.signOutCalls,       1 );
    });

    testWidgets( "AuthInitial → AuthError calls onSignedOut (defensive tear-down)", ( tester ) async {
      whenListen(
        auth,
        Stream<AuthState>.fromIterable( [
          const AuthError( message: "boom", lastEmail: "a@b.com" ),
        ] ),
        initialState: const AuthInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pumpAndSettle();

      expect( hooks.authenticatedCalls, isEmpty );
      expect( hooks.signOutCalls,       1 );
    });

    testWidgets( "AuthInitial → AuthBiometricRequired is a no-op (no access token yet)", ( tester ) async {
      whenListen(
        auth,
        Stream<AuthState>.fromIterable( [
          const AuthBiometricRequired( email: "a@b.com" ),
        ] ),
        initialState: const AuthInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pumpAndSettle();

      expect( hooks.authenticatedCalls, isEmpty );
      expect( hooks.signOutCalls,       0 );
    });
  });
}

class _FakeHooks {
  final List<String> authenticatedCalls = [];
  int signOutCalls = 0;

  Future<void> onAuthenticated( String userId ) async {
    authenticatedCalls.add( userId );
  }

  Future<void> onSignedOut() async {
    signOutCalls += 1;
  }
}

class _Sentinel extends StatelessWidget {
  const _Sentinel();
  @override
  Widget build( BuildContext context ) => const Scaffold(
    body: Center( child: Text( "SENTINEL" ) ),
  );
}
