// Row e0f0faf0, finding follow-up: the server log showed POST /auth/logout answering 422 and
// POST /api/fcm/unregister-token answering 401 from the phone.
//
// 422: the route takes a body { refresh_token } and the phone sent none.
// 401: the unregister ran after the access token was cleared, so it went out without a bearer.
//
// These tests pin the two fixes at the bloc: the refresh token reaches the repository, and the
// before-sign-out hook runs while the access token is still set.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/features/auth/domain/auth_bloc.dart';
import 'package:lupin_mobile/features/auth/domain/auth_event.dart';
import 'package:lupin_mobile/features/auth/domain/auth_state.dart';
import 'package:lupin_mobile/services/auth/auth_repository.dart';
import 'package:lupin_mobile/services/auth/auth_token_provider.dart';
import 'package:lupin_mobile/services/auth/biometric_gate.dart';
import 'package:lupin_mobile/services/auth/secure_credential_store.dart';
import 'package:lupin_mobile/services/auth/server_context_service.dart';

class _MockRepo      extends Mock implements AuthRepository {}
class _MockBiometric extends Mock implements BiometricGate {}

/// A store whose refresh-token read throws, as a locked or corrupted keystore does.
class _ThrowingReadStore extends SecureCredentialStore {
  _ThrowingReadStore() : super( const FlutterSecureStorage() );

  @override
  Future<String?> readRefreshToken( String contextId ) async => throw Exception( "keystore unavailable" );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final shippedJson = File( "assets/config/server-contexts.json" ).readAsStringSync();

  late ServerContextService  svc;
  late SecureCredentialStore store;
  late _MockRepo             repo;
  late List<String>          events;
  late String?               accessTokenSeenByHook;

  AuthBloc build( { Future<void> Function()? hook } ) => AuthBloc(
    repo            : repo,
    store           : store,
    context         : svc,
    biometric       : _MockBiometric(),
    onBeforeSignOut : hook,
  );

  setUp( () async {
    SharedPreferences.setMockInitialValues( {} );
    FlutterSecureStorage.setMockInitialValues( {
      "auth.dev.refresh_token"   : "fake-refresh-value",
      "auth.dev.last_email"      : "dev@x.y",
    } );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler( "flutter/assets", ( message ) async {
        final key = const StringCodec().decodeMessage( message );
        return key == "assets/config/server-contexts.json"
          ? const StringCodec().encodeMessage( shippedJson )
          : null;
      } );

    svc                   = await ServerContextService.load( await SharedPreferences.getInstance() );
    store                 = SecureCredentialStore( const FlutterSecureStorage() );
    repo                  = _MockRepo();
    events                = [];
    accessTokenSeenByHook = null;
    setAccessToken( "fake-access-value" );

    when( () => repo.logout( any(), refreshToken: any( named: "refreshToken" ) ) )
      .thenAnswer( ( _ ) async { events.add( "server-logout" ); } );
  } );

  tearDown( () => clearAccessToken() );

  test( "logout hands the stored refresh token to the repository", () async {
    final bloc = build();
    bloc.add( const AuthLogoutRequested() );
    await bloc.stream.firstWhere( ( s ) => s is AuthUnauthenticated );

    verify( () => repo.logout( "fake-access-value", refreshToken: "fake-refresh-value" ) ).called( 1 );
    await bloc.close();
  } );

  test( "the before-sign-out hook runs while the access token is still set", () async {
    final bloc = build( hook: () async {
      accessTokenSeenByHook = readAccessToken();
      events.add( "unregister-push" );
    } );
    bloc.add( const AuthLogoutRequested() );
    await bloc.stream.firstWhere( ( s ) => s is AuthUnauthenticated );

    expect( accessTokenSeenByHook, "fake-access-value", reason: "cleared first, the unregister goes out bearerless and gets a 401" );
    expect( events, [ "unregister-push", "server-logout" ] );
    expect( readAccessToken(), isNull );
    await bloc.close();
  } );

  test( "a failing before-sign-out hook still completes the logout and clears local tokens", () async {
    final bloc = build( hook: () async { throw Exception( "push unregister failed" ); } );
    bloc.add( const AuthLogoutRequested() );
    await bloc.stream.firstWhere( ( s ) => s is AuthUnauthenticated );

    expect( readAccessToken(), isNull );
    expect( await store.readRefreshToken( "dev" ), isNull );
    verify( () => repo.logout( any(), refreshToken: any( named: "refreshToken" ) ) ).called( 1 );
    await bloc.close();
  } );

  test( "a server-switch logout also unregisters push before the token is cleared", () async {
    final bloc = build( hook: () async { accessTokenSeenByHook = readAccessToken(); } );
    bloc.add( const AuthServerContextSwitchRequested( "lan-dev" ) );
    await bloc.stream.firstWhere( ( s ) => s is AuthUnauthenticated );

    expect( accessTokenSeenByHook, "fake-access-value" );
    await bloc.close();
  } );

  test( "a throwing refresh-token read still completes the logout and clears local tokens", () async {
    final bloc = AuthBloc( repo: repo, store: _ThrowingReadStore(), context: svc, biometric: _MockBiometric() );
    bloc.add( const AuthLogoutRequested() );
    final state = await bloc.stream.firstWhere( ( s ) => s is AuthUnauthenticated );

    expect( state, isA<AuthUnauthenticated>() );
    expect( readAccessToken(), isNull, reason: "the user must not stay signed in because storage could not be read" );
    await bloc.close();
  } );

  test( "a throwing refresh-token read still completes a server switch", () async {
    final bloc = AuthBloc( repo: repo, store: _ThrowingReadStore(), context: svc, biometric: _MockBiometric() );
    bloc.add( const AuthServerContextSwitchRequested( "lan-dev" ) );
    await bloc.stream.firstWhere( ( s ) => s is AuthUnauthenticated );

    expect( svc.active, "lan-dev" );
    expect( readAccessToken(), isNull );
    await bloc.close();
  } );
}
