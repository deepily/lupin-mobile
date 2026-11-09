import 'dart:async';

/// Tracks the loudest level a recorder reports while a capture runs.
///
/// A capture that reaches the server as silence is transcribed as "thank you".
/// This reads the level while the microphone is open, so a silent capture shows in the trace before the server is blamed.
/// Levels are decibels relative to full scale: 0 is the loudest, and about -160 is silence.
class PeakMeter {
  /// How often the level is read.
  static const Duration defaultInterval = Duration( milliseconds: 100 );

  /// Below this the capture is treated as silent.
  ///
  /// Speech into a phone or earbud microphone peaks well above it.
  static const double silentBelowDb = -50;

  /// Reads the current level in decibels, or null when the recorder has none.
  final Future<double?> Function() _read;
  /// How often [_read] is called.
  final Duration interval;

  Timer?  _timer;
  double? _peak;
  int     _samples = 0;

  /// Creates a meter that reads through [read] every [interval].
  PeakMeter( { required Future<double?> Function() read, this.interval = defaultInterval } ) : _read = read;

  /// The loudest level read so far, or null before the first reading.
  double? get peakDb => _peak;

  /// How many readings succeeded.
  int get samples => _samples;

  /// Starts reading, forgetting any earlier run.
  ///
  /// Ensures:
  ///   - a reading that throws or returns null is skipped, never raised
  void start() {
    stop();
    _peak    = null;
    _samples = 0;
    _timer   = Timer.periodic( interval, ( _ ) => _sample() );
  }

  /// Stops reading; [peakDb] and [samples] keep their values.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _sample() async {
    try {
      final level = await _read();
      if ( level == null || level.isNaN ) return;
      _samples++;
      if ( _peak == null || level > _peak! ) _peak = level;
    } catch ( _ ) {
      // A missed reading costs one sample; the capture itself is untouched.
    }
  }

  /// One line for the trace: the peak, the reading count, and whether the capture looks silent.
  String describe() {
    final peak = _peak;
    if ( peak == null ) return 'peakDb=none samples=$_samples';
    return 'peakDb=${ peak.toStringAsFixed( 1 ) } samples=$_samples${ peak < silentBelowDb ? " SILENT" : "" }';
  }
}
