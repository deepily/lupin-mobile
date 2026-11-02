/// The media session drives the podcast, or Quick Ask while it holds the earbud presses.
library;

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/services/audio/lupin_media_handler.dart';

class _Transport implements MediaTransport {
  final calls = <String>[];
  @override
  Duration position = Duration.zero;
  @override
  Future<void> play()  async => calls.add( 'play' );
  @override
  Future<void> pause() async => calls.add( 'pause' );
  @override
  Future<void> seek( Duration p ) async => calls.add( 'seek ${ p.inSeconds }' );
  @override
  Future<void> stop()  async => calls.add( 'stop' );
}

class _Claimant implements MediaButtonClaimant {
  final presses = <MediaButton>[];
  @override
  void onMediaButton( MediaButton button ) => presses.add( button );
}

const _card    = MediaItem( id: 'qa', title: 'Quick Ask' );
const _episode = MediaItem( id: 'pg-1', title: 'Episode' );

void main() {
  late LupinMediaHandler handler;
  late _Transport        transport;

  setUp( () {
    handler   = LupinMediaHandler( rewindInterval: const Duration( seconds: 15 ) );
    transport = _Transport();
    handler.attach( transport );
  } );

  void playing( bool on ) => handler.reportPodcast(
    playing: on, processingState: AudioProcessingState.ready, position: const Duration( seconds: 30 ) );

  group( 'with no claimant, a press drives the podcast', () {
    test( 'a tap while paused plays, and a tap while playing pauses', () async {
      playing( false );
      await handler.click();
      playing( true );
      await handler.click();
      expect( transport.calls, [ 'play', 'pause' ] );
    } );

    test( 'rewind backs up the interval and stops at the start', () async {
      transport.position = const Duration( seconds: 40 );
      await handler.rewind();
      transport.position = const Duration( seconds: 5 );
      await handler.rewind();
      expect( transport.calls, [ 'seek 25', 'seek 0' ] );
    } );

    test( 'fast forward jumps ahead, and seek and stop pass through', () async {
      transport.position = const Duration( seconds: 40 );
      await handler.fastForward();
      await handler.seek( const Duration( seconds: 7 ) );
      await handler.stop();
      expect( transport.calls, [ 'seek 50', 'seek 7', 'stop' ] );
      expect( handler.playbackState.value.processingState, AudioProcessingState.idle );
    } );

    test( 'the podcast state shows on the session, and is not playing once finished', () {
      playing( true );
      expect( handler.playbackState.value.playing, isTrue );
      expect( handler.playbackState.value.controls.first, MediaControl.pause );
      handler.reportPodcast( playing: true, processingState: AudioProcessingState.completed, position: Duration.zero );
      expect( handler.playbackState.value.playing, isFalse );
    } );

    test( 'the track shows as the card', () {
      handler.showTrack( _episode );
      expect( handler.mediaItem.value, _episode );
    } );

    test( 'with no player attached, the controls do nothing and do not throw', () async {
      final bare = LupinMediaHandler( rewindInterval: const Duration( seconds: 15 ) );
      await bare.click();
      await bare.pause();
      await bare.rewind();
      await bare.fastForward();
      await bare.seek( Duration.zero );
    } );
  } );

  group( 'while Quick Ask holds the presses', () {
    test( 'every press goes to it, and none reaches the podcast', () async {
      final quickAsk = _Claimant();
      await handler.claim( quickAsk, card: _card );
      await handler.click();
      await handler.click( MediaButton.next );
      expect( quickAsk.presses, [ MediaButton.media, MediaButton.next ] );
      expect( transport.calls, isEmpty );
      expect( handler.isClaimed, isTrue );
    } );

    test( 'a playing podcast pauses, and the session shows the Quick Ask card as active', () async {
      handler.showTrack( _episode );
      playing( true );
      await handler.claim( _Claimant(), card: _card );
      expect( transport.calls, [ 'pause' ] );
      expect( handler.mediaItem.value, _card );
      expect( handler.playbackState.value.playing, isTrue );
    } );

    test( 'podcast updates are kept but not shown until release', () async {
      final quickAsk = _Claimant();
      handler.showTrack( _episode );
      await handler.claim( quickAsk, card: _card );
      playing( false );
      handler.showTrack( _episode );
      expect( handler.mediaItem.value, _card );

      handler.release( quickAsk );
      expect( handler.isClaimed, isFalse );
      expect( handler.mediaItem.value, _episode );
      expect( handler.playbackState.value.playing, isFalse );
      expect( handler.playbackState.value.controls.first, MediaControl.play );
    } );

    test( 'after release a press drives the podcast again', () async {
      final quickAsk = _Claimant();
      await handler.claim( quickAsk, card: _card );
      handler.release( quickAsk );
      await handler.click();
      expect( quickAsk.presses, isEmpty );
      expect( transport.calls, [ 'play' ] );
    } );

    test( 'a release by a replaced claimant leaves the new one holding the presses', () async {
      final first  = _Claimant();
      final second = _Claimant();
      await handler.claim( first, card: _card );
      await handler.claim( second, card: _card );
      handler.release( first );
      await handler.click();
      expect( second.presses, [ MediaButton.media ] );
      expect( first.presses, isEmpty );
    } );

    test( 'with no podcast ever loaded, release leaves an idle session', () async {
      final quickAsk = _Claimant();
      await handler.claim( quickAsk, card: _card );
      handler.release( quickAsk );
      expect( handler.mediaItem.value, isNull );
      expect( handler.playbackState.value.playing, isFalse );
      expect( handler.playbackState.value.processingState, AudioProcessingState.idle );
    } );
  } );
}
