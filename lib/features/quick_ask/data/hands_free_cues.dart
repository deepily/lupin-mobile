import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import '../domain/earbud_taps.dart';

/// Plays the tone for each [HandsFreeCue].
abstract interface class HandsFreeCuePlayer {
  /// Plays [cue]'s tone; it doesn't wait for the tone to end.
  Future<void> play( HandsFreeCue cue );
}

/// The real player: short tones built in memory, played through the media stream.
///
/// The media stream reaches the earbuds. Playing it also keeps this app the one
/// Android sends the next earbud press to.
class ToneCuePlayer implements HandsFreeCuePlayer {
  final AudioPlayer _player;
  final Map<HandsFreeCue, Uint8List> _tones = {
    for ( final cue in HandsFreeCue.values ) cue: CueTones.wav( cue ),
  };

  /// Creates the player; [player] is a test seam, production passes nothing.
  ToneCuePlayer( { AudioPlayer? player } ) : _player = player ?? AudioPlayer() {
    _player.setAudioContext( const AudioContext(
      android: AudioContextAndroid(
        contentType : AndroidContentType.sonification,
        usageType   : AndroidUsageType.media,
        audioFocus  : AndroidAudioFocus.gainTransientMayDuck,
      ),
    ) );
  }

  /// Plays [cue], cutting off one still playing.
  ///
  /// Each `play` takes audio focus again and audioplayers releases only the latest request, so the stop keeps focus from leaking.
  @override
  Future<void> play( HandsFreeCue cue ) async {
    await _player.stop();
    await _player.play( BytesSource( _tones[ cue ]! ) );
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
