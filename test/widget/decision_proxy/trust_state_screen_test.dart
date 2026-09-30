import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/decision_proxy/data/decision_proxy_models.dart';
import 'package:lupin_mobile/features/decision_proxy/domain/decision_proxy_bloc.dart';
import 'package:lupin_mobile/features/decision_proxy/domain/decision_proxy_event.dart';
import 'package:lupin_mobile/features/decision_proxy/domain/decision_proxy_state.dart';
import 'package:lupin_mobile/features/decision_proxy/presentation/trust_state_screen.dart';

import '../../_harness/test_app.dart';

/// Widget-level coverage for the TrustStateScreen drilldown
/// (per-domain trust details, accessed from TrustDashboardScreen AppBar).
void main() {
  setUpAll( registerHarnessFallbacks );

  group( "TrustStateScreen", () {
    late MockDecisionProxyBloc bloc;

    TrustStateItem item( {
      required String id,
      required String domain,
      required String category,
      int trustLevel = 2,
      int totalDecisions = 10,
      int successfulDecisions = 7,
      int rejectedDecisions = 3,
      String? circuitBreakerState,
    } ) => TrustStateItem(
      id                  : id,
      domain              : domain,
      category            : category,
      trustLevel          : trustLevel,
      totalDecisions      : totalDecisions,
      successfulDecisions : successfulDecisions,
      rejectedDecisions   : rejectedDecisions,
      circuitBreakerState : circuitBreakerState,
    );

    setUp(() {
      bloc = MockDecisionProxyBloc();
    });

    Widget underTest() {
      return testApp(
        authBloc: MockAuthBloc(),
        extraProviders: [
          BlocProvider<DecisionProxyBloc>.value( value: bloc ),
        ],
        child: const TrustStateScreen( userEmail: "u@x.y" ),
      );
    }

    testWidgets( "dispatches LoadTrust on mount and renders trust-state rows", ( tester ) async {
      whenListen(
        bloc,
        Stream<DecisionProxyState>.fromIterable( [
          const DecisionProxyLoading(),
          DecisionProxyTrustLoaded(
            TrustStateResponse(
              status      : "ok",
              userEmail   : "u@x.y",
              trustStates : [
                item( id: "1", domain: "swe", category: "edit"   ),
                item( id: "2", domain: "swe", category: "delete" ),
                item( id: "3", domain: "web", category: "fetch"  ),
              ],
            ),
          ),
        ] ),
        initialState: const DecisionProxyInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();
      await tester.pump();

      verify( () => bloc.add( any(
        that: isA<DecisionProxyLoadTrust>().having(
          ( e ) => e.userEmail, "userEmail", "u@x.y",
        ),
      ) ) ).called( 1 );

      expect( find.byKey( Key( '${TestKeys.trustStateRowPrefix}swe:edit'   ) ), findsOneWidget );
      expect( find.byKey( Key( '${TestKeys.trustStateRowPrefix}swe:delete' ) ), findsOneWidget );
      expect( find.byKey( Key( '${TestKeys.trustStateRowPrefix}web:fetch'  ) ), findsOneWidget );
    });

    testWidgets( "renders empty-state when trustStates is empty", ( tester ) async {
      whenListen(
        bloc,
        Stream<DecisionProxyState>.fromIterable( [
          const DecisionProxyTrustLoaded(
            TrustStateResponse(
              status      : "ok",
              userEmail   : "u@x.y",
              trustStates : [],
            ),
          ),
        ] ),
        initialState: const DecisionProxyInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      expect( find.text( "No trust states" ), findsOneWidget );
    });

    testWidgets( "renders error state from DecisionProxyError", ( tester ) async {
      whenListen(
        bloc,
        Stream<DecisionProxyState>.fromIterable( [
          const DecisionProxyError( "trust unavailable" ),
        ] ),
        initialState: const DecisionProxyInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      expect( find.text( "trust unavailable" ), findsOneWidget );
    });

    testWidgets( "groups rows by domain with section headers", ( tester ) async {
      whenListen(
        bloc,
        Stream<DecisionProxyState>.fromIterable( [
          DecisionProxyTrustLoaded(
            TrustStateResponse(
              status      : "ok",
              userEmail   : "u@x.y",
              trustStates : [
                item( id: "1", domain: "swe", category: "edit"  ),
                item( id: "2", domain: "web", category: "fetch" ),
              ],
            ),
          ),
        ] ),
        initialState: const DecisionProxyInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      expect( find.byKey( Key( '${TestKeys.trustStateDomainHeaderPrefix}swe' ) ), findsOneWidget );
      expect( find.byKey( Key( '${TestKeys.trustStateDomainHeaderPrefix}web' ) ), findsOneWidget );
    });

    testWidgets( "shows circuit-open chip when circuitBreakerState is open", ( tester ) async {
      whenListen(
        bloc,
        Stream<DecisionProxyState>.fromIterable( [
          DecisionProxyTrustLoaded(
            TrustStateResponse(
              status      : "ok",
              userEmail   : "u@x.y",
              trustStates : [
                item( id: "1", domain: "swe", category: "edit", circuitBreakerState: "open"   ),
                item( id: "2", domain: "swe", category: "scan", circuitBreakerState: "closed" ),
              ],
            ),
          ),
        ] ),
        initialState: const DecisionProxyInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      // exactly one circuit-open chip rendered (the row with circuitBreakerState=open)
      expect( find.text( "circuit open" ), findsOneWidget );
    });
  });
}
