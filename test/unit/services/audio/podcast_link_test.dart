import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/services/audio/podcast_link.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test( "Wi-Fi and Ethernet are unmetered, none is offline, everything else is metered", () {
    expect( podcastLinkOf( ConnectivityResult.wifi ),      PodcastLink.unmetered );
    expect( podcastLinkOf( ConnectivityResult.ethernet ),  PodcastLink.unmetered );
    expect( podcastLinkOf( ConnectivityResult.none ),      PodcastLink.offline );
    expect( podcastLinkOf( ConnectivityResult.mobile ),    PodcastLink.metered );
    expect( podcastLinkOf( ConnectivityResult.vpn ),       PodcastLink.metered );
    expect( podcastLinkOf( ConnectivityResult.bluetooth ), PodcastLink.metered );
    expect( podcastLinkOf( ConnectivityResult.other ),     PodcastLink.metered );
  } );

  test( "currentPodcastLink reads connectivity_plus", () async {
    const channel   = MethodChannel( "dev.fluttercommunity.plus/connectivity" );
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown( () => messenger.setMockMethodCallHandler( channel, null ) );
    for ( final entry in { "wifi": PodcastLink.unmetered, "mobile": PodcastLink.metered, "none": PodcastLink.offline }.entries ) {
      messenger.setMockMethodCallHandler( channel, ( _ ) async => entry.key );
      expect( await currentPodcastLink(), entry.value, reason: entry.key );
    }
  } );
}
