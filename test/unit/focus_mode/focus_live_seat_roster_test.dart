/// Rick 2026-09-17: on a cold start this morning no seat he hadn't already
/// heard from was on the rail, so he had to open the browser to start a
/// conversation he could then follow on the phone. The rail now also merges
/// the LIVE-SEAT roster (`/api/commons/active-sessions`, read from the session
/// bridges) and a toolbar refresh re-reads both lists.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_bloc.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_event.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_state.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/features/notifications/data/notification_repository.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';

class _MockRepo extends Mock implements NotificationRepository {}
class _MockTts  extends Mock implements TtsOrchestrator {}

const String _written = 'claude.code@lupin.deepily.ai#d1e0fd28';   // has messaged him
const String _silent  = 'claude.code@lupin-mobile.deepily.ai#7e82da5f';   // live, never has

void main() {
  group( 'the rail merges the live-seat roster', () {
    late _MockRepo repo;
    late _MockTts  tts;
    late DateTime  clock;
    FocusChatBloc? bloc;

    setUp( () {
      repo  = _MockRepo();
      tts   = _MockTts();
      clock = DateTime.utc( 2026, 9, 17, 19, 30 );
      when( () => repo.sendersVisible( any(), hours: any( named: 'hours' ) ) )
          .thenAnswer( ( _ ) async => [
            SenderSummary(
              senderId     : _written,
              lastActivity : clock.subtract( const Duration( minutes: 5 ) ),
              count        : 3,
              voicePersona : const VoicePersona( name: 'Mr. Radio', icon: '🦉' ),
            ),
          ] );
      bloc = FocusChatBloc( repo, tts: tts, now: () => clock );
    } );

    tearDown( () async => bloc?.close() );

    Future<void> pump() => Future<void>.delayed( const Duration( milliseconds: 10 ) );

    ActiveSession seat( String? senderId, { DateTime? lastSeen, String? name, String icon = '💍' } ) =>
        ActiveSession(
          sessionId : 'sess',
          senderId  : senderId,
          persona   : name == null ? null : VoicePersona( name: name, icon: icon ),
          lastSeen  : lastSeen,
        );

    Future<void> coldStart() async {
      bloc!.add( const FocusColdStartRequested( userEmail: 'ricardo.felipe.ruiz@gmail.com' ) );
      await pump();
    }

    test( 'a live seat that has never written appears on the rail, with its bridge persona', () async {
      when( () => repo.activeSessions() ).thenAnswer( ( _ ) async => [
        seat( _silent, lastSeen: clock.subtract( const Duration( minutes: 2 ) ), name: 'Tiffany' ),
      ] );

      await coldStart();

      expect( bloc!.state.senderOrder, containsAll( [ _written, _silent ] ) );
      expect( bloc!.state.personasBySender[ _silent ]?.name, 'Tiffany' );
      expect( bloc!.state.bandFor( _silent ), FocusBand.live,
          reason: 'last_seen_iso feeds the Live band' );
      expect( bloc!.state.visibleOrder, containsAll( [ _written, _silent ] ),
          reason: 'both reachable through the default Personas + Live lens' );
      expect( bloc!.state.windows[ _silent ] ?? const [], isEmpty,
          reason: 'listed with no messages — the composer is what writes to it' );
    } );

    test( 'a seat the server cannot address is skipped rather than guessed at', () async {
      when( () => repo.activeSessions() ).thenAnswer( ( _ ) async => [
        seat( null, lastSeen: clock, name: 'María' ),   // older server: session_id only
      ] );

      await coldStart();

      expect( bloc!.state.senderOrder, [ _written ] );
      expect( bloc!.state.personasBySender.containsKey( 'sess' ), isFalse );
    } );

    test( 'the roster never overwrites what a real message established', () async {
      final fromMessage = clock.subtract( const Duration( minutes: 5 ) );
      when( () => repo.activeSessions() ).thenAnswer( ( _ ) async => [
        // Same sender, but the bridge is STALER and names a different persona.
        seat( _written, lastSeen: clock.subtract( const Duration( hours: 3 ) ), name: 'Stale' ),
      ] );

      await coldStart();

      expect( bloc!.state.personasBySender[ _written ]?.name, 'Mr. Radio' );
      expect( bloc!.state.lastActivityBySender[ _written ], fromMessage,
          reason: 'a stale bridge stamp never drags a sender backwards' );
    } );

    test( 'a roster failure is not fatal — the written-senders rail still stands', () async {
      when( () => repo.activeSessions() ).thenThrow(
          const NotificationApiException( 'List active sessions failed', statusCode: 500 ) );

      await coldStart();

      expect( bloc!.state.senderOrder, [ _written ] );
      expect( bloc!.state.hydration, FocusHydration.ready,
          reason: 'the roster is an ADDITION; losing it is not an error state' );
    } );

    test( 'the toolbar refresh re-reads both lists and picks up a seat spawned since', () async {
      when( () => repo.activeSessions() ).thenAnswer( ( _ ) async => const [] );
      await coldStart();
      expect( bloc!.state.senderOrder, [ _written ] );

      when( () => repo.activeSessions() ).thenAnswer( ( _ ) async => [
        seat( _silent, lastSeen: clock, name: 'Tiffany' ),
      ] );
      bloc!.add( const FocusRosterRefreshRequested() );
      await pump();

      expect( bloc!.state.senderOrder, containsAll( [ _written, _silent ] ) );
      verify( () => repo.sendersVisible( any(), hours: any( named: 'hours' ) ) ).called( 2 );
      verify( () => repo.activeSessions() ).called( 2 );
    } );

    test( 'refresh before any cold start fetches nothing — there is no user to fetch for', () async {
      when( () => repo.activeSessions() ).thenAnswer( ( _ ) async => const [] );

      bloc!.add( const FocusRosterRefreshRequested() );
      await pump();

      verifyNever( () => repo.activeSessions() );
      verifyNever( () => repo.sendersVisible( any(), hours: any( named: 'hours' ) ) );
    } );
  } );
}
