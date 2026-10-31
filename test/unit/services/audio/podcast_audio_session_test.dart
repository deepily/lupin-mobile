import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/services/audio/podcast_audio_session.dart';

class _MockSession extends Mock implements AudioSession {}
class _FakeConfig  extends Fake implements AudioSessionConfiguration {}

void main() {
  setUpAll( () => registerFallbackValue( _FakeConfig() ) );

  test( "configures the session so a duck arrives as a pause", () async {
    final session = _MockSession();
    AudioSessionConfiguration? seen;
    when( () => session.configure( any() ) ).thenAnswer( ( inv ) async {
      seen = inv.positionalArguments.first as AudioSessionConfiguration;
    } );

    await configurePodcastAudioSession( session );

    verify( () => session.configure( any() ) ).called( 1 );
    expect( seen!.androidWillPauseWhenDucked, isTrue );
    expect( seen!.androidAudioAttributes!.contentType, AndroidAudioContentType.speech );
    expect( seen!.androidAudioAttributes!.usage,       AndroidAudioUsage.media );
    expect( seen!.avAudioSessionMode,                  AVAudioSessionMode.spokenAudio );
  } );
}
