import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

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
      when( () => ctx.activeConfig ).thenReturn( testContextConfig() );
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
  });
}

class _SentinelChild extends StatelessWidget {
  const _SentinelChild();
  @override
  Widget build( BuildContext context ) => const Scaffold(
    body: Center( child: Text( "AUTH_SENTINEL" ) ),
  );
}
