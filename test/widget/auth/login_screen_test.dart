import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
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
      when( () => ctx.activeConfig ).thenReturn( testContextConfig() );
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
}
