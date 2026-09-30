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
import 'package:lupin_mobile/features/decision_proxy/presentation/trust_dashboard_screen.dart';

import '../../_harness/test_app.dart';

/// Widget-level coverage for Smoke B2 (Trust Dashboard renders). Exercises
/// the LoadDashboard-on-mount + mode header + pending/empty rendering
/// without an emulator round-trip.
void main() {
  setUpAll( registerHarnessFallbacks );

  group( "TrustDashboardScreen", () {
    late MockDecisionProxyBloc bloc;

    TrustModeStatus modeActive() => const TrustModeStatus(
      status        : "ok",
      iniMode       : TrustMode.active,
      runningMode   : null,
      effective     : TrustMode.active,
      hasRunningJob : false,
    );

    PendingSummary emptySummary() => const PendingSummary(
      totalPending : 0,
      byCategory   : {},
      byTrustLevel : {},
    );

    ProxyDecision pd( String id ) => ProxyDecision(
      id                : id,
      domain            : "swe",
      category          : "edit",
      question          : "Approve this change?",
      action            : "suggest",
      confidence        : 0.85,
      trustLevel        : 2,
      reason            : "high confidence",
      ratificationState : "pending",
      dataOrigin        : "organic",
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
        child: const TrustDashboardScreen( userEmail: "u@x.y" ),
      );
    }

    testWidgets( "dispatches LoadDashboard on mount and renders mode + decisions", ( tester ) async {
      whenListen(
        bloc,
        Stream<DecisionProxyState>.fromIterable( [
          const DecisionProxyLoading(),
          DecisionProxyDashboardLoaded(
            mode    : modeActive(),
            pending : [ pd( "d-1" ), pd( "d-2" ) ],
            summary : emptySummary(),
          ),
        ] ),
        initialState: const DecisionProxyInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();
      await tester.pump();

      verify( () => bloc.add( any(
        that: isA<DecisionProxyLoadDashboard>().having(
          ( e ) => e.userEmail, "userEmail", "u@x.y",
        ),
      ) ) ).called( 1 );

      expect( find.textContaining( "Effective: active" ), findsOneWidget );
      expect( find.byType( SegmentedButton<TrustMode> ), findsOneWidget );
      // Two decision cards.
      expect( find.text( "Approve this change?" ), findsNWidgets( 2 ) );
    });

    testWidgets( "renders empty-state when no pending decisions", ( tester ) async {
      whenListen(
        bloc,
        Stream<DecisionProxyState>.fromIterable( [
          DecisionProxyDashboardLoaded(
            mode    : modeActive(),
            pending : const [],
            summary : emptySummary(),
          ),
        ] ),
        initialState: const DecisionProxyInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      expect( find.text( "No pending decisions" ), findsOneWidget );
    });

    testWidgets( "renders error state", ( tester ) async {
      whenListen(
        bloc,
        Stream<DecisionProxyState>.fromIterable( [
          const DecisionProxyError( "proxy down" ),
        ] ),
        initialState: const DecisionProxyInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      expect( find.text( "proxy down" ), findsOneWidget );
    });

    testWidgets( "tapping approve on a decision dispatches DecisionProxyRatify(approved: true)", ( tester ) async {
      final decision = pd( "d-42" );
      whenListen(
        bloc,
        Stream<DecisionProxyState>.fromIterable( [
          DecisionProxyDashboardLoaded(
            mode    : modeActive(),
            pending : [ decision ],
            summary : emptySummary(),
          ),
        ] ),
        initialState: const DecisionProxyInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      expect( find.byKey( Key( '${TestKeys.trustDecisionCardPrefix}d-42' ) ), findsOneWidget );
      await tester.tap( find.byKey( Key( '${TestKeys.trustDecisionApprovePrefix}d-42' ) ) );
      await tester.pump();

      final captured = verify( () => bloc.add( captureAny(
        that: isA<DecisionProxyRatify>(),
      ) ) ).captured;
      // LoadDashboard fires on mount too, so we look for the Ratify specifically.
      final ratify = captured.whereType<DecisionProxyRatify>().single;
      expect( ratify.decisionId, "d-42" );
      expect( ratify.approved,   isTrue );
      expect( ratify.userEmail,  "u@x.y" );
    });

    testWidgets( "tapping reject on a decision dispatches DecisionProxyRatify(approved: false)", ( tester ) async {
      final decision = pd( "d-43" );
      whenListen(
        bloc,
        Stream<DecisionProxyState>.fromIterable( [
          DecisionProxyDashboardLoaded(
            mode    : modeActive(),
            pending : [ decision ],
            summary : emptySummary(),
          ),
        ] ),
        initialState: const DecisionProxyInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      await tester.tap( find.byKey( Key( '${TestKeys.trustDecisionRejectPrefix}d-43' ) ) );
      await tester.pump();

      final captured = verify( () => bloc.add( captureAny(
        that: isA<DecisionProxyRatify>(),
      ) ) ).captured;
      final ratify = captured.whereType<DecisionProxyRatify>().single;
      expect( ratify.decisionId, "d-43" );
      expect( ratify.approved,   isFalse );
    });
  });
}
