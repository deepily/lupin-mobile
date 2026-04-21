import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/features/agentic/domain/agentic_submission_bloc.dart';
import 'package:lupin_mobile/features/agentic/domain/agentic_submission_event.dart';
import 'package:lupin_mobile/features/agentic/domain/agentic_submission_state.dart';
import 'package:lupin_mobile/features/auth/domain/auth_bloc.dart';
import 'package:lupin_mobile/features/auth/domain/auth_event.dart';
import 'package:lupin_mobile/features/auth/domain/auth_state.dart';
import 'package:lupin_mobile/features/decision_proxy/domain/decision_proxy_bloc.dart';
import 'package:lupin_mobile/features/decision_proxy/domain/decision_proxy_event.dart';
import 'package:lupin_mobile/features/decision_proxy/domain/decision_proxy_state.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_bloc.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_event.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_state.dart';
import 'package:lupin_mobile/services/auth/server_context_service.dart';

/// Mocktail fallback registration — call once from main() of any test that
/// uses `any()` over these types. Safe to call multiple times.
void registerHarnessFallbacks() {
  registerFallbackValue( const AuthStarted() );
  registerFallbackValue( const AuthUnauthenticated() );
  registerFallbackValue( const NotificationsLoadInbox( userEmail: "u@x.y" ) );
  registerFallbackValue( const NotificationsGenerateGistRequested() );
  registerFallbackValue( const NotificationsInitial() );
  registerFallbackValue( const DecisionProxyLoadDashboard( "u@x.y" ) );
  registerFallbackValue( const DecisionProxyInitial() );
  registerFallbackValue( const AgenticFormReset() );
  registerFallbackValue( const AgenticSubmissionInitial() );
}

class MockAuthBloc              extends MockBloc<AuthEvent, AuthState>                         implements AuthBloc {}
class MockNotificationBloc      extends MockBloc<NotificationEvent, NotificationState>         implements NotificationBloc {}
class MockDecisionProxyBloc     extends MockBloc<DecisionProxyEvent, DecisionProxyState>       implements DecisionProxyBloc {}
class MockAgenticSubmissionBloc extends MockBloc<AgenticSubmissionEvent, AgenticSubmissionState> implements AgenticSubmissionBloc {}

class MockServerContextService extends Mock implements ServerContextService {}

/// Stand-in [ServerContextConfig] so tests can stub `activeConfig`
/// without reaching into the real ServerContextService implementation.
ServerContextConfig testContextConfig( { String label = "DEV" } ) {
  return ServerContextConfig(
    id      : "dev",
    label   : label,
    baseUrl : "http://10.0.2.2:7999",
    wsUrl   : "ws://10.0.2.2:7999",
  );
}

/// Wraps [child] in a MaterialApp + MultiBlocProvider for widget tests.
///
/// Pass a pre-configured [authBloc] (typically a [MockAuthBloc] with
/// `whenListen` set up) to exercise login/auth flows. Additional providers
/// can be injected via [extraProviders].
Widget testApp( {
  required AuthBloc authBloc,
  required Widget child,
  List<BlocProvider> extraProviders = const [],
} ) {
  return MaterialApp(
    home: MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>.value( value: authBloc ),
        ...extraProviders,
      ],
      child: child,
    ),
  );
}
