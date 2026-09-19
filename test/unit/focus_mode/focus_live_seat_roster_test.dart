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

  // Row cea58ee0 (Rick, P0): Krishna, Rio and Rachel each appeared twice. The
  // server resolves a seat's project inside a container that cannot see the
  // host path, so a WORKTREE seat is served as `claude.code@seat-…#hash`
  // while its own notifications say `claude.code@lupin…#hash`. Same session
  // hash, same seat — one row.
  group( 'one seat, one row, whatever project segment the roster sends', () {
    const String hash     = 'a1b2c3d4';
    const String real     = 'claude.code@lupin.deepily.ai#$hash';
    const String alias    = 'claude.code@seat-cc-author-mr-radio-2.deepily.ai#$hash';

    late _MockRepo repo;
    late _MockTts  tts;
    late DateTime  clock;
    FocusChatBloc? bloc;

    setUp( () {
      repo  = _MockRepo();
      tts   = _MockTts();
      clock = DateTime.utc( 2026, 9, 18, 21, 0 );
      when( () => tts.enqueueAlways(
        message  : any( named: 'message'  ),
        priority : any( named: 'priority' ),
        title    : any( named: 'title'    ),
        voiceId  : any( named: 'voiceId'  ),
        sender   : any( named: 'sender'   ),
        verbatim : any( named: 'verbatim' ),
      ) ).thenReturn( null );
      when( () => repo.conversation( any(), any(), hours: any( named: 'hours' ) ) )
          .thenAnswer( ( _ ) async => const [] );
      bloc = FocusChatBloc( repo, tts: tts, now: () => clock );
    } );

    tearDown( () async => bloc?.close() );

    Future<void> pump() => Future<void>.delayed( const Duration( milliseconds: 10 ) );

    ActiveSession seat( String sid, String name ) => ActiveSession(
      sessionId : 'sess-$name',
      senderId  : sid,
      persona   : VoicePersona( name: name, icon: '🙂' ),
      lastSeen  : clock,
    );

    test( 'the exact report: three worktree seats that have written, served under seat-… ids', () async {
      final seats = {
        'Krishna' : '11111111',
        'Rio'     : '22222222',
        'Rachel'  : '33333333',
      };
      when( () => repo.sendersVisible( any(), hours: any( named: 'hours' ) ) ).thenAnswer( ( _ ) async => [
        for ( final e in seats.entries ) SenderSummary(
          senderId     : 'claude.code@lupin.deepily.ai#${e.value}',
          lastActivity : clock.subtract( const Duration( minutes: 3 ) ),
          count        : 2,
          voicePersona : VoicePersona( name: e.key, icon: '🙂' ),
        ),
      ] );
      when( () => repo.activeSessions() ).thenAnswer( ( _ ) async => [
        for ( final e in seats.entries )
          seat( 'claude.code@seat-cc-author-mr-radio-2.deepily.ai#${e.value}', e.key ),
      ] );

      bloc!.add( const FocusColdStartRequested( userEmail: 'ricardo.felipe.ruiz@gmail.com' ) );
      await pump();

      expect( bloc!.state.senderOrder, [
        for ( final h in seats.values ) 'claude.code@lupin.deepily.ai#$h',
      ], reason: 'three seats, three rows, all under the id their messages carry' );
      for ( final h in seats.values ) {
        expect( bloc!.state.lastActivityBySender[ 'claude.code@lupin.deepily.ai#$h' ], clock,
            reason: 'the roster still bumps the real row: the seat is live' );
      }
    } );

    test( 'a roster alias seen FIRST is replaced in place when the seat first speaks', () async {
      when( () => repo.sendersVisible( any(), hours: any( named: 'hours' ) ) )
          .thenAnswer( ( _ ) async => const [] );
      when( () => repo.activeSessions() ).thenAnswer( ( _ ) async => [ seat( alias, 'Rio' ) ] );
      bloc!.add( const FocusColdStartRequested( userEmail: 'ricardo.felipe.ruiz@gmail.com' ) );
      await pump();
      bloc!.add( const FocusSenderSelected( alias ) );   // he opened it before it ever spoke
      await pump();
      expect( bloc!.state.senderOrder, [ alias ] );

      bloc!.add( FocusInboundNotification( NotificationItem(
        id: 'n1', message: 'hello from Rio', type: 'task', priority: 'low', senderId: real,
        timestamp: clock, played: true, playCount: 0, responseRequested: false,
        suppressDing: true, displayQualifierWidget: false,
      ) ) );
      await pump();

      expect( bloc!.state.senderOrder, [ real ], reason: 'the alias is gone, not kept beside it' );
      expect( bloc!.state.focusedSender, real, reason: 'focus follows the seat' );
      expect( bloc!.state.personasBySender[ real ]?.name, 'Rio' );
      expect( bloc!.state.windows[ real ]!.single.item.message, 'hello from Rio' );
    } );

    test( 'a different session with the same persona name is NOT merged', () async {
      when( () => repo.sendersVisible( any(), hours: any( named: 'hours' ) ) ).thenAnswer( ( _ ) async => [
        SenderSummary( senderId: real, lastActivity: clock, count: 1,
            voicePersona: const VoicePersona( name: 'Rio', icon: '🙂' ) ),
      ] );
      const other = 'claude.code@seat-cc-author-maria-2.deepily.ai#99999999';
      when( () => repo.activeSessions() ).thenAnswer( ( _ ) async => [ seat( other, 'Rio' ) ] );

      bloc!.add( const FocusColdStartRequested( userEmail: 'ricardo.felipe.ruiz@gmail.com' ) );
      await pump();

      expect( bloc!.state.senderOrder, [ real, other ],
          reason: 'identity is the session hash, never the persona name' );
    } );
  } );

  group( 'sessionHashOf', () {
    test( 'reads the 8 hex after the #, and nothing without one', () {
      expect( sessionHashOf( 'claude.code@lupin.deepily.ai#a1b2c3d4' ), 'a1b2c3d4' );
      expect( sessionHashOf( 'queue.done@lupin.deepily.ai' ), isNull );
      expect( sessionHashOf( 'x#' ), isNull );
      expect( sessionHashOf( null ), isNull );
    } );
  } );
}
