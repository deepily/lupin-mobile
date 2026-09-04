/// Bug 9adff476 — the DI seam, not the logic.
///
/// `FocusChatBloc` has accepted an `isQuickAskJob` probe since the verbatim
/// contract was written (rnd 2026.08.29 §71), and `actionable_speech_test`
/// has always proved the LOGIC works when that probe is supplied. Production
/// never supplied it. The suite stayed green the whole time, because a test
/// that hands in the dependency it is exercising cannot fail on that
/// dependency being absent everywhere else.
///
/// This file asserts the one thing that file structurally cannot: that the
/// PRODUCTION construction wires the probe. Delete the injection from
/// `ServiceLocator.buildFocusChatBloc` and this goes red;
/// `actionable_speech_test` stays green.
///
/// It calls the extracted production factory rather than `ServiceLocator
/// .init()`, which needs `path_provider` platform channels — the reason the
/// existing DI suite sits in `legacy_quarantine` and the reason nothing was
/// watching this seam in the first place.
library;

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/core/di/service_locator.dart';
import 'package:lupin_mobile/features/notifications/data/notification_repository.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_bloc.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_event.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_state.dart';
import 'package:lupin_mobile/services/notification_filter/notification_stop_list.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';

class _MockRepo     extends Mock implements NotificationRepository {}
class _MockTts      extends Mock implements TtsOrchestrator {}
class _MockStopList extends Mock implements NotificationStopList {}

class _MockQuickAsk extends MockBloc<QuickAskEvent, QuickAskState>
    implements QuickAskBloc {}

void main() {
  final getIt = GetIt.instance;

  group( 'DI wiring — Quick Ask verbatim probe (bug 9adff476)', () {
    late _MockQuickAsk quickAsk;

    setUp( () {
      quickAsk = _MockQuickAsk();
      getIt
        ..registerSingleton<NotificationRepository>( _MockRepo() )
        ..registerSingleton<TtsOrchestrator>( _MockTts() )
        ..registerSingleton<NotificationStopList>( _MockStopList() )
        ..registerSingleton<QuickAskBloc>( quickAsk );
    } );

    tearDown( () async {
      await getIt.reset();
    } );

    test( 'production construction supplies a non-null isQuickAskJob', () async {
      final focus = ServiceLocator.buildFocusChatBloc();
      addTearDown( focus.close );

      expect(
        focus.hasQuickAskProbe,
        isTrue,
        reason: 'buildFocusChatBloc must pass isQuickAskJob. Without it '
                'shouldSpeakVerbatim short-circuits at speech_intent.dart:83, '
                'and the answer the user ASKED for is cut to ttsFraction — or, '
                'with speakSystemSenders off, never spoken at all.',
      );
    } );

    test( 'the probe resolves QuickAskBloc lazily, not at build time', () async {
      // QuickAskBloc is registered AFTER FocusChatBloc in the real locator, so
      // the callback must defer its lookup to CALL time. Proven by building
      // with NO QuickAskBloc registered: a tear-off would throw here.
      await getIt.unregister<QuickAskBloc>();

      final focus = ServiceLocator.buildFocusChatBloc();
      addTearDown( focus.close );

      expect( focus.hasQuickAskProbe, isTrue,
              reason: 'building must not require QuickAskBloc to exist yet' );
    } );
  } );
}
