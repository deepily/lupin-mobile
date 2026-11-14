import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/logging/logger.dart';
import '../../../services/audio/lupin_media_handler.dart';
import '../domain/earbud_taps.dart';

/// Plays the tone for each [HandsFreeCue].
abstract interface class HandsFreeCuePlayer {
  /// Plays [cue]'s tone; it doesn't wait for the tone to end.
  Future<void> play( HandsFreeCue cue );
}

/// The real player: short tones built in memory, played through just_audio.
///
/// The media stream reaches the earbuds.
/// Android sends an earbud press to the app whose player started last, so each tone also wins the next press.
/// It must be just_audio, as the podcast uses: Android never logged the audioplayers tone players as started.
/// The player takes no audio focus, so a tone pauses nothing.
class ToneCuePlayer implements HandsFreeCuePlayer {
  final AudioPlayer Function()                  _create;
  final Future<String> Function( HandsFreeCue ) _toneFile;
  AudioPlayer? _player;

  /// Creates the player; [create] and [toneFile] are test seams, production passes nothing.
  ///
  /// The player is built on the first [play], after `AudioService.init` has run.
  ToneCuePlayer( { AudioPlayer Function()? create, Future<String> Function( HandsFreeCue )? toneFile } )
      : _create   = create ?? _newPlayer,
        _toneFile = toneFile ?? CueToneFiles.path;

  static AudioPlayer _newPlayer() => AudioPlayer( handleInterruptions: false, handleAudioSessionActivation: false );

  /// Plays [cue], cutting off one still playing.
  ///
  /// Ensures:
  ///   - returns once the tone is loaded, without waiting for it to end
  ///   - a tone that fails to play is logged, never thrown later
  @override
  Future<void> play( HandsFreeCue cue ) async {
    final player = _player ??= _create();
    await player.stop();
    await player.setFilePath( await _toneFile( cue ) );
    // just_audio's play() completes only when playback stops, so it is not awaited.
    unawaited( player.play().catchError( ( Object e, StackTrace s ) {
      Logger.warning( 'cue: ${ cue.name } failed: $e', tag: LupinMediaHandler.logTag, error: e, stackTrace: s );
    } ) );
  }
}

/// Each tone as a WAV file in the temporary folder, since just_audio plays files.
class CueToneFiles {
  CueToneFiles._();

  static final Map<HandsFreeCue, Future<String>> _written = {};

  /// The path of [cue]'s tone file, writing it the first time it is asked for.
  ///
  /// Ensures:
  ///   - the file holds exactly [CueTones.wav] for [cue]
  ///   - a failed write is not cached, so the next call tries again
  static Future<String> path( HandsFreeCue cue ) =>
      _written[ cue ] ??= _write( cue ).catchError( ( Object e ) {
        _written.remove( cue );
        throw e;
      } );

  static Future<String> _write( HandsFreeCue cue ) async {
    final dir  = await getTemporaryDirectory();
    final file = File( '${ dir.path }/hands-free-cue-${ cue.name }.wav' );
    await file.writeAsBytes( CueTones.wav( cue ), flush: true );
    return file.path;
  }
}

/// The tones, as mono 16-bit PCM WAV bytes.
///
/// Ready is one short beep, started rises and stopped falls.
/// Sent climbs three steps, and refused is one low buzz.
/// So each can be told apart without looking.
class CueTones {
  CueTones._();

  /// Samples per second.
  static const int sampleRate = 16000;

  static const _beep = 0.09;
  static const _gap  = 0.03;

  /// The ( Hz, seconds ) notes of each cue; a 0 Hz note is silence.
  static const Map<HandsFreeCue, List<( double, double )>> notes = {
    HandsFreeCue.ready   : [ ( 880, 0.06 ) ],
    HandsFreeCue.started : [ ( 660, _beep ), ( 0, _gap ), ( 880, _beep ) ],
    HandsFreeCue.stopped : [ ( 880, _beep ), ( 0, _gap ), ( 660, _beep ) ],
    HandsFreeCue.sent    : [ ( 660, 0.07 ), ( 0, _gap ), ( 880, 0.07 ), ( 0, _gap ), ( 1100, 0.07 ) ],
    HandsFreeCue.refused : [ ( 220, 0.25 ) ],
  };

  /// Builds [cue]'s tone.
  ///
  /// Ensures:
  ///   - returns a 44-byte PCM WAV header followed by the samples
  ///   - each note fades in and out over 5 ms, so it starts and ends without a click
  static Uint8List wav( HandsFreeCue cue ) {
    final samples = <int>[];
    for ( final ( hz, seconds ) in notes[ cue ]! ) {
      final count = ( sampleRate * seconds ).round();
      const fade  = sampleRate * 0.005;
      for ( var i = 0; i < count; i++ ) {
        final edge = math.min( 1.0, math.min( i, count - 1 - i ) / fade );
        final wave = hz == 0 ? 0.0 : math.sin( 2 * math.pi * hz * i / sampleRate );
        samples.add( ( wave * edge * 0.4 * 32767 ).round() );
      }
    }
    final dataBytes = samples.length * 2;
    final bytes     = Uint8List( 44 + dataBytes );
    final view      = ByteData.view( bytes.buffer );
    void ascii( int at, String s ) => bytes.setRange( at, at + 4, s.codeUnits );
    ascii( 0, 'RIFF' );
    view.setUint32( 4, 36 + dataBytes, Endian.little );
    ascii( 8, 'WAVE' );
    ascii( 12, 'fmt ' );
    view.setUint32( 16, 16,             Endian.little );
    view.setUint16( 20, 1,              Endian.little );
    view.setUint16( 22, 1,              Endian.little );
    view.setUint32( 24, sampleRate,     Endian.little );
    view.setUint32( 28, sampleRate * 2, Endian.little );
    view.setUint16( 32, 2,              Endian.little );
    view.setUint16( 34, 16,             Endian.little );
    ascii( 36, 'data' );
    view.setUint32( 40, dataBytes,      Endian.little );
    for ( var i = 0; i < samples.length; i++ ) {
      view.setInt16( 44 + i * 2, samples[ i ], Endian.little );
    }
    return bytes;
  }
}
