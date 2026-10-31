import 'package:audio_session/audio_session.dart';

/// Configures [session] for podcast playback.
///
/// Uses the speech recipe, which sets `androidWillPauseWhenDucked`. A short spoken alert asks Android for
/// ducking focus. With that flag the podcast receives it as a pause and resumes when the alert ends,
/// instead of only playing quieter under it.
///
/// Requires:
///   - call once at startup, before the first track is loaded
///
/// Ensures:
///   - [session] is configured with `AudioSessionConfiguration.speech()`
Future<void> configurePodcastAudioSession( AudioSession session ) =>
    session.configure( const AudioSessionConfiguration.speech() );
