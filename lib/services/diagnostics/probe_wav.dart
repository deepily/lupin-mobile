import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

/// Deterministic in-memory WAV clip for the network round-trip probe.
///
/// Generated rather than bundled so the APK does not grow by megabytes: a
/// linear frequency sweep (220 Hz → 1760 Hz) at moderate amplitude, mono,
/// 16-bit PCM, wrapped in a canonical 44-byte RIFF/WAVE header. The same
/// arguments always produce the same bytes.
class ProbeWav {
  ProbeWav._();

  static const int headerBytes    = 44;
  static const int bitsPerSample  = 16;
  static const int numChannels    = 1;
  static const int defaultSeconds = 30;

  static const double _startHz   = 220.0;
  static const double _endHz     = 1760.0;
  static const double _amplitude = 0.3;

  /// Total file length for a clip of [seconds] at [sampleRate].
  ///
  /// Requires:
  ///   - sampleRate > 0 and seconds > 0
  ///
  /// Ensures:
  ///   - returns 44 + sampleRate * seconds * 2 (mono, 2 bytes per sample)
  static int byteLength( { required int sampleRate, int seconds = defaultSeconds } ) =>
      headerBytes + sampleRate * seconds * numChannels * ( bitsPerSample ~/ 8 );

  /// Build the clip.
  ///
  /// Requires:
  ///   - sampleRate > 0 and seconds > 0
  ///
  /// Ensures:
  ///   - returns exactly [byteLength] bytes
  ///   - bytes 0-43 are a valid PCM RIFF/WAVE header for mono 16-bit audio
  ///   - output is identical for identical arguments
  ///
  /// Raises:
  ///   - ArgumentError if sampleRate or seconds is not positive
  static Uint8List generate( { required int sampleRate, int seconds = defaultSeconds } ) {
    if ( sampleRate <= 0 ) throw ArgumentError.value( sampleRate, 'sampleRate', 'must be positive' );
    if ( seconds    <= 0 ) throw ArgumentError.value( seconds, 'seconds', 'must be positive' );

    final totalBytes  = byteLength( sampleRate: sampleRate, seconds: seconds );
    final dataBytes   = totalBytes - headerBytes;
    const blockAlign  = numChannels * ( bitsPerSample ~/ 8 );
    final byteRate    = sampleRate * blockAlign;
    final bytes       = Uint8List( totalBytes );
    final view        = ByteData.view( bytes.buffer );

    void ascii( int offset, String s ) {
      for ( var i = 0; i < s.length; i++ ) {
        bytes[ offset + i ] = s.codeUnitAt( i );
      }
    }

    ascii( 0, 'RIFF' );
    view.setUint32( 4, totalBytes - 8, Endian.little );
    ascii( 8, 'WAVE' );
    ascii( 12, 'fmt ' );
    view.setUint32( 16, 16,            Endian.little ); // fmt chunk size
    view.setUint16( 20, 1,             Endian.little ); // PCM
    view.setUint16( 22, numChannels,   Endian.little );
    view.setUint32( 24, sampleRate,    Endian.little );
    view.setUint32( 28, byteRate,      Endian.little );
    view.setUint16( 32, blockAlign,    Endian.little );
    view.setUint16( 34, bitsPerSample, Endian.little );
    ascii( 36, 'data' );
    view.setUint32( 40, dataBytes,     Endian.little );

    final sampleCount = dataBytes ~/ blockAlign;
    final duration    = seconds.toDouble();
    final sweepRate   = ( _endHz - _startHz ) / ( 2.0 * duration );
    for ( var n = 0; n < sampleCount; n++ ) {
      final t     = n / sampleRate;
      final phase = 2.0 * math.pi * ( _startHz * t + sweepRate * t * t );
      final value = ( math.sin( phase ) * _amplitude * 32767.0 ).round();
      view.setInt16( headerBytes + n * blockAlign, value, Endian.little );
    }
    return bytes;
  }

  /// Build the clip on a background isolate so the UI thread never stalls.
  ///
  /// Requires:
  ///   - sampleRate > 0 and seconds > 0
  ///
  /// Ensures:
  ///   - completes with exactly the bytes [generate] returns for the same
  ///     arguments
  ///
  /// Raises:
  ///   - ArgumentError (through the future) if sampleRate or seconds is not
  ///     positive
  static Future<Uint8List> generateInBackground( { required int sampleRate, int seconds = defaultSeconds } ) =>
      Isolate.run( () => generate( sampleRate: sampleRate, seconds: seconds ) );
}
