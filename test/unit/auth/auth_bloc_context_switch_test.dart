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

/// Review race on 597c5dc: the switch sent a logout event and then switched
/// the context straight away, so the logout handler ran against the NEW
/// context and cleared the wrong server's session. The switch is now one
/// AuthBloc event that clears the old session before switching.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final shippedJson = File( "assets/config/server-contexts.json" ).readAsStringSync();

  late ServerContextService  svc;
  late SecureCredentialStore store;
  late _MockRepo             repo;
  late AuthBloc              bloc;

  setUp( () async {
    SharedPreferences.setMockInitialValues( {} );
    FlutterSecureStorage.setMockInitialValues( {
      "auth.dev.refresh_token"         : "dev-refresh",
      "auth.dev.last_email"            : "dev@x.y",
      "auth.dev.session.dev@x.y"       : "dev-session",
      "auth.lan-dev.refresh_token"     : "lan-refresh",
      "auth.lan-dev.last_email"        : "lan@x.y",
      "auth.lan-dev.session.lan@x.y"   : "lan-session",
    } );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler( "flutter/assets", ( message ) async {
        final key = const StringCodec().decodeMessage( message );
        return key == "assets/config/server-contexts.json"
          ? const StringCodec().encodeMessage( shippedJson )
          : null;
      } );

    svc   = await ServerContextService.load( await SharedPreferences.getInstance() );
    store = SecureCredentialStore( const FlutterSecureStorage() );
    repo  = _MockRepo();
    bloc  = AuthBloc( repo: repo, store: store, context: svc, biometric: _MockBiometric() );
  } );

  tearDown( () async {
    await bloc.close();
    clearAccessToken();
  } );

  test( "switching dev -> lan-dev clears the OLD (dev) session and leaves lan-dev's untouched", () async {
    String? activeAtLogout;
    setAccessToken( "dev-access" );
    when( () => repo.logout( any() ) ).thenAnswer( ( _ ) async { activeAtLogout = svc.active; } );

    bloc.add( const AuthServerContextSwitchRequested( "lan-dev" ) );
    final state = await bloc.stream.firstWhere( ( s ) => s is AuthUnauthenticated );

    expect( svc.active, "lan-dev" );
    expect( activeAtLogout, "dev", reason: "the server logout goes to the server you were signed in to" );
    expect( readAccessToken(), isNull );

    expect( await store.readRefreshToken( "dev" ), isNull );
    expect( await store.readSessionId( "dev", "dev@x.y" ), isNull );
    expect( await store.readLastEmail( "dev" ), "dev@x.y", reason: "last email is kept for pre-fill" );

    expect( await store.readRefreshToken( "lan-dev" ), "lan-refresh" );
    expect( await store.readSessionId( "lan-dev", "lan@x.y" ), "lan-session" );
    expect( ( state as AuthUnauthenticated ).lastEmail, "lan@x.y" );
  } );

  test( "a failing server logout still clears the old session and switches", () async {
    setAccessToken( "dev-access" );
    when( () => repo.logout( any() ) ).thenThrow( const AuthException( "offline" ) );

    bloc.add( const AuthServerContextSwitchRequested( "lan-dev" ) );
    await bloc.stream.firstWhere( ( s ) => s is AuthUnauthenticated );

    expect( svc.active, "lan-dev" );
    expect( await store.readRefreshToken( "dev" ),     isNull );
    expect( await store.readRefreshToken( "lan-dev" ), "lan-refresh" );
  } );

  test( "picking the server that is already active does nothing", () async {
    bloc.add( const AuthServerContextSwitchRequested( "dev" ) );
    await Future<void>.delayed( const Duration( milliseconds: 50 ) );

    expect( svc.active, "dev" );
    expect( await store.readRefreshToken( "dev" ), "dev-refresh" );
    verifyNever( () => repo.logout( any() ) );
  } );
}
