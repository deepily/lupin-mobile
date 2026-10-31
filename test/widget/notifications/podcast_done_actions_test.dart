import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/artifacts/podcast_play.dart';
import 'package:lupin_mobile/features/notifications/presentation/podcast_done_actions.dart';

/// P4: Play on a podcast-done card.

const String _oneLanguage =
    "**Podcast Activity Report**\n\n**Segments**: 4\n"
    "**English**: [📝 Script](/app/docs?path=io%2Fa.md) | [▶️ Play Here](/app/audio?path=io%2Fa.mp3&embed=1) | "
    "[🎧 Listen](/app/audio?path=io%2Fa.mp3) | [⬇️ Download](/api/io/file?path=io%2Fa.mp3&download=true)\n";

const String _twoLanguages =
    "$_oneLanguage"
    "**Mexican Spanish**: [▶️ Play Here](/app/audio?path=io%2Fb.mp3&embed=1)\n";

void main() {
  Future<List<List<String>>> pump(
    WidgetTester tester, {
    required String? abstractText,
  } ) async {
    final played = <List<String>>[];
    await tester.pumpWidget( MaterialApp(
      home: Scaffold(
        body: PodcastDoneActions(
          abstractText: abstractText,
          onPlay      : ( url, title ) async => played.add( [ url, title ] ),
        ),
      ),
    ) );
    return played;
  }

  testWidgets( "Play is present and hands the audio link and a title to the player", ( tester ) async {
    final played = await pump( tester, abstractText: _oneLanguage );
    expect( find.text( "Play" ), findsOneWidget );

    await tester.tap( find.byKey( const Key( "${TestKeys.podcastPlayPrefix}0" ) ) );
    expect( played, [ [ "io/a.mp3", "English" ] ] );
  } );

  testWidgets( "one Play per language when there are several", ( tester ) async {
    final played = await pump( tester, abstractText: _twoLanguages );
    expect( find.text( "Play English" ), findsOneWidget );
    expect( find.text( "Play Mexican Spanish" ), findsOneWidget );

    await tester.tap( find.byKey( const Key( "${TestKeys.podcastPlayPrefix}1" ) ) );
    expect( played.single.first, "io/b.mp3" );
  } );

  testWidgets( "an abstract with no audio renders nothing", ( tester ) async {
    await pump( tester, abstractText: "**Segments**: 4" );
    expect( find.byType( FilledButton ), findsNothing );
  } );

  testWidgets( "the default Play opens the player page for the audio path", ( tester ) async {
    await tester.pumpWidget( const MaterialApp(
      home: Scaffold( body: PodcastDoneActions( abstractText: _oneLanguage ) ),
    ) );
    await tester.tap( find.byKey( const Key( "${TestKeys.podcastPlayPrefix}0" ) ) );
    await tester.pump();
    await tester.pump( const Duration( milliseconds: 400 ) );
    expect( find.text( "Audio — English" ), findsOneWidget );
  } );

  group( "parsing", () {
    test( "audio parsing handles null, empty, a bare download link and a line without a label", () {
      expect( parsePodcastAudio( null ), isEmpty );
      expect( parsePodcastAudio( "" ), isEmpty );
      final bare = parsePodcastAudio( "[⬇️ Download](/api/io/file?path=io%2Fz.mp3&download=true)" );
      expect( bare.single.label, "Podcast" );
      expect( bare.single.url, "io/z.mp3" );
    } );

    test( "audioPathOf decodes the path query and leaves a bare path alone", () {
      expect( audioPathOf( "/api/io/file?path=io%2Fa.mp3" ), "io/a.mp3" );
      expect( audioPathOf( "io/a.mp3" ), "io/a.mp3" );
    } );
  } );
}
