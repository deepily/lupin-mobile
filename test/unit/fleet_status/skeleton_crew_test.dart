/// Skeleton crew models, repository write and bloc, over the captured wire bodies.
///
/// The five bodies came from the real lupin route handlers.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/fleet_status/data/fleet_models.dart';
import 'package:lupin_mobile/features/fleet_status/data/fleet_repository.dart';
import 'package:lupin_mobile/features/fleet_status/data/fleet_watchable_models.dart';
import 'package:lupin_mobile/features/fleet_status/domain/fleet_status_bloc.dart';

import '../_helpers/stub_dio.dart';

late Map<String, Map<String, Object?>> wire;

Object? body( String name )   => wire[ name ]![ "body" ];
int     status( String name ) => wire[ name ]![ "status" ] as int;

class _FakeRepo implements FleetRepository {
  Map<String, Object?> capBody  = {};
  Map<String, Object?>? putBody;
  Object?              putThrows;
  final List<bool>     writes   = [];
  int                  capReads = 0;

  @override
  Future<FleetComposite> fetchState( { CancelToken? cancelToken } ) async =>
      const FleetComposite();

  @override
  Future<Map<String, Object?>> fetchSizeCap( { CancelToken? cancelToken } ) async {
    capReads++;
    return capBody;
  }

  @override
  Future<FleetWatchableRoster> fetchWatchable( { CancelToken? cancelToken } ) async =>
      FleetWatchableRoster.none;

  @override
  Future<Map<String, Object?>> setSkeletonCrew( bool on ) async {
    writes.add( on );
    if ( putThrows != null ) throw putThrows!;
    return putBody!;
  }

  @override
  Future<Map<String, Object?>> setSizeCap( int cap ) async => capBody;
}

Map<String, Object?> asMap( Object? o ) => Map<String, Object?>.from( o as Map );

void main() {
  setUpAll( () {
    final raw = jsonDecode( File(
      "test/fixtures/fleet_status/skeleton_crew_wire_2026.10.10.json" ).readAsStringSync() ) as Map;
    wire = raw.map( ( k, v ) => MapEntry( k as String, asMap( v ) ) );
  } );

  group( "SkeletonCrew.fromCapBody — the captured bodies", () {
    test( "never flipped: off, no author, no time, no mute", () {
      final s = SkeletonCrew.fromCapBody( body( "get_never_flipped" ) )!;
      expect( s.on, isFalse );
      expect( s.since, isNull );
      expect( s.setBy, isNull );
      expect( s.settingsMuteWhileOff, isFalse );
    } );

    test( "PUT on: on, with author and time", () {
      final s = SkeletonCrew.fromCapBody( body( "put_on" ) )!;
      expect( s.on, isTrue );
      expect( s.setBy, "rick@example.com" );
      expect( s.since, "2026-10-10T13:25:43.079954-04:00" );
    } );

    test( "off while the settings mute is set: warning flag true", () {
      final s = SkeletonCrew.fromCapBody( body( "put_off_while_settings_mute_is_set" ) )!;
      expect( s.on, isFalse );
      expect( s.settingsMuteWhileOff, isTrue );
    } );

    test( "settings file unreadable: flag is null, not false", () {
      final s = SkeletonCrew.fromCapBody( body( "get_settings_file_unreadable" ) )!;
      expect( s.settingsMuteWhileOff, isNull );
    } );

    test( "an older server sends no skeleton_crew: null", () {
      final old = asMap( body( "get_never_flipped" ) )..remove( "skeleton_crew" );
      expect( SkeletonCrew.fromCapBody( old ), isNull );
    } );

    test( "on that is not a boolean: null, so the switch stays hidden", () {
      for ( final bad in <Object?>[ "true", 1, null ] ) {
        final b = asMap( body( "put_on" ) );
        b[ "skeleton_crew" ] = { ...asMap( b[ "skeleton_crew" ] ), "on": bad };
        expect( SkeletonCrew.fromCapBody( b ), isNull, reason: "on=$bad" );
      }
    } );

    test( "skeleton_crew that is not an object, or a body that is not a map: null", () {
      expect( SkeletonCrew.fromCapBody( { "skeleton_crew": true } ), isNull );
      expect( SkeletonCrew.fromCapBody( "x" ), isNull );
      expect( SkeletonCrew.fromCapBody( null ), isNull );
    } );

    test( "a non-bool mute flag reads as unknown, not as a warning", () {
      final b = asMap( body( "put_on" ) );
      b[ "skeleton_crew" ] = { ...asMap( b[ "skeleton_crew" ] ), "on": false,
                               "settings_mute_while_off": "yes" };
      expect( SkeletonCrew.fromCapBody( b )!.settingsMuteWhileOff, isNull );
    } );
  } );

  group( "FleetRepository.setSkeletonCrew", () {
    FleetRepository repoWith( StubAdapter a ) => FleetRepository( makeDio( a ) );

    test( "PUTs {on: true} to /api/arbiter/skeleton-crew and returns the re-read", () async {
      final a = StubAdapter( {
        "PUT ${ FleetRepository.skeletonCrewEndpoint }" : ( _ ) =>
            jsonBody( body( "put_on" ), status: status( "put_on" ) ),
      } );
      final answer = await repoWith( a ).setSkeletonCrew( true );

      expect( FleetRepository.skeletonCrewEndpoint, "/api/arbiter/skeleton-crew" );
      expect( a.captured.single.method, "PUT" );
      expect( a.captured.single.data, { "on": true } );
      expect( SkeletonCrew.fromCapBody( answer )!.on, isTrue );
    } );

    test( "a 403 raises with the server's sentence verbatim and status 403", () async {
      final a = StubAdapter( {
        "PUT ${ FleetRepository.skeletonCrewEndpoint }" : ( _ ) => jsonBody(
            body( "put_refused_for_an_api_key" ),
            status: status( "put_refused_for_an_api_key" ) ),
      } );
      await expectLater(
        repoWith( a ).setSkeletonCrew( false ),
        throwsA( isA<FleetApiException>()
            .having( ( e ) => e.message, "message",
                     "Only an administrator may change the skeleton crew switch." )
            .having( ( e ) => e.statusCode, "statusCode", 403 ) ),
      );
    } );

    test( "a 409 and a 500 carry their detail; a 422 list falls back to the status", () async {
      for ( final c in <( int, Object, String )>[
        ( 409, { "detail": "key defined twice: lines 4 and 9" }, "key defined twice: lines 4 and 9" ),
        ( 500, { "detail": "could not write" },                 "could not write" ),
        ( 422, { "detail": [ { "loc": [ "body", "on" ] } ] },    "HTTP 422" ),
      ] ) {
        final a = StubAdapter( {
          "PUT ${ FleetRepository.skeletonCrewEndpoint }" : ( _ ) => jsonBody( c.$2, status: c.$1 ),
        } );
        await expectLater(
          repoWith( a ).setSkeletonCrew( true ),
          throwsA( isA<FleetApiException>().having( ( e ) => e.message, "message", c.$3 ) ),
          reason: "status ${ c.$1 }",
        );
      }
    } );

    test( "a transport failure raises FleetApiException", () async {
      final dio = Dio( BaseOptions( baseUrl: "http://test" ) )
        ..httpClientAdapter = _Boom();
      await expectLater(
        FleetRepository( dio ).setSkeletonCrew( true ),
        throwsA( isA<FleetApiException>() ),
      );
    } );
  } );

  group( "FleetRepository.setSizeCap — a 403 from the admin-only cap PUT", () {
    test( "raises with the server's sentence, so the dial can report it", () async {
      final a = StubAdapter( {
        "PUT ${ FleetRepository.fleetSizeCapEndpoint }" : ( _ ) => jsonBody(
            { "detail": "Only an administrator may set the fleet size cap." }, status: 403 ),
      } );
      await expectLater(
        FleetRepository( makeDio( a ) ).setSizeCap( 5 ),
        throwsA( isA<FleetApiException>()
            .having( ( e ) => e.message, "message",
                     "Only an administrator may set the fleet size cap." )
            .having( ( e ) => e.statusCode, "statusCode", 403 ) ),
      );
    } );
  } );

  group( "FleetStatusBloc", () {
    test( "a poll reads the switch and the ceiling from the real body", () async {
      final repo = _FakeRepo()..capBody = asMap( body( "put_off_while_settings_mute_is_set" ) );
      final bloc = FleetStatusBloc( repo );
      await bloc.pollOnce( CancelToken() );
      await Future<void>.delayed( Duration.zero );

      expect( bloc.state.skeletonCrew!.on, isFalse );
      expect( bloc.state.skeletonCrew!.settingsMuteWhileOff, isTrue );
      expect( bloc.state.cap, 8 );
      expect( bloc.state.capMaximum, 18, reason: "the real key is `ceiling`" );
      await bloc.close();
    } );

    test( "an older server's poll clears the switch", () async {
      final repo = _FakeRepo()..capBody = asMap( body( "put_on" ) );
      final bloc = FleetStatusBloc( repo );
      await bloc.pollOnce( CancelToken() );
      await Future<void>.delayed( Duration.zero );
      expect( bloc.state.skeletonCrew, isNotNull );

      repo.capBody = { "cap": 8, "ceiling": 18 };
      await bloc.pollOnce( CancelToken() );
      await Future<void>.delayed( Duration.zero );
      expect( bloc.state.skeletonCrew, isNull );
      await bloc.close();
    } );

    test( "setSkeletonCrew adopts the server's answer, not the request", () async {
      final repo = _FakeRepo()
        ..capBody = asMap( body( "get_never_flipped" ) )
        // The operator asks for ON; the file says OFF with a mute warning.
        ..putBody = asMap( body( "put_off_while_settings_mute_is_set" ) );
      final bloc = FleetStatusBloc( repo );
      await bloc.pollOnce( CancelToken() );
      await Future<void>.delayed( Duration.zero );

      await bloc.setSkeletonCrew( true );
      await Future<void>.delayed( Duration.zero );

      expect( repo.writes, [ true ], reason: "one flip, one write" );
      expect( bloc.state.skeletonCrew!.on, isFalse );
      expect( bloc.state.skeletonCrew!.settingsMuteWhileOff, isTrue );
      await bloc.close();
    } );

    test( "a refusal re-reads the GET and rethrows the server's exception", () async {
      final repo = _FakeRepo()
        ..capBody   = asMap( body( "put_on" ) )
        ..putThrows = const FleetApiException(
            "Only an administrator may change the skeleton crew switch.", statusCode: 403 );
      final bloc = FleetStatusBloc( repo );
      await bloc.pollOnce( CancelToken() );
      await Future<void>.delayed( Duration.zero );
      final readsBefore = repo.capReads;

      await expectLater( bloc.setSkeletonCrew( false ), throwsA( isA<FleetApiException>() ) );
      await Future<void>.delayed( Duration.zero );

      expect( repo.capReads, readsBefore + 1, reason: "snap back by re-reading" );
      expect( bloc.state.skeletonCrew!.on, isTrue, reason: "the server's state, not the request" );
      await bloc.close();
    } );

    test( "setCap keeps the switch the last poll established", () async {
      final repo = _FakeRepo()..capBody = asMap( body( "put_on" ) );
      final bloc = FleetStatusBloc( repo );
      await bloc.pollOnce( CancelToken() );
      await Future<void>.delayed( Duration.zero );

      repo.capBody = { "cap": 9, "ceiling": 18 };   // a cap PUT answer carries no switch
      await bloc.setCap( 9 );
      await Future<void>.delayed( Duration.zero );

      expect( bloc.state.cap, 9 );
      expect( bloc.state.skeletonCrew!.on, isTrue );
      await bloc.close();
    } );
  } );
}

class _Boom implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch( RequestOptions o, Stream<dynamic>? s, Future? c ) async =>
      throw DioException( requestOptions: o, type: DioExceptionType.connectionError,
                          message: "no route to host" );
  @override
  void close( { bool force = false } ) {}
}
