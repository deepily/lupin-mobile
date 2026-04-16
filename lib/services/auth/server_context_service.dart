import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';

enum ServerContext { dev, test }

class ServerContextConfig {
  final String id;
  final String label;
  final String baseUrl;
  final String wsUrl;

  const ServerContextConfig( {
    required this.id,
    required this.label,
    required this.baseUrl,
    required this.wsUrl,
  } );

  factory ServerContextConfig.fromJson( String id, Map<String, dynamic> json ) {
    return ServerContextConfig(
      id      : id,
      label   : json["label"] as String,
      baseUrl : json["baseUrl"] as String,
      wsUrl   : json["wsUrl"] as String,
    );
  }
}

/// Resolves the active server context (dev / test) and exposes its
/// base URL + WS URL. Persists the user's last selection via
/// SharedPreferences (non-secret; URLs are not sensitive).
class ServerContextService {
  static const String _assetPath    = "assets/config/server-contexts.json";
  static const String _prefsKey     = "active_server_context";

  final SharedPreferences _prefs;
  final Map<ServerContext, ServerContextConfig> _contexts;
  ServerContext _active;

  ServerContextService._( this._prefs, this._contexts, this._active );

  /// Load the bundled config and resolve the previously-selected context
  /// (or the file's declared default on first launch).
  static Future<ServerContextService> load( SharedPreferences prefs ) async {
    final raw  = await rootBundle.loadString( _assetPath );
    final json = jsonDecode( raw ) as Map<String, dynamic>;

    final contextsJson = json["contexts"] as Map<String, dynamic>;
    final contexts     = <ServerContext, ServerContextConfig>{};
    for ( final entry in contextsJson.entries ) {
      final ctx = _parseContext( entry.key );
      if ( ctx == null ) continue;
      contexts[ ctx ] = ServerContextConfig.fromJson(
        entry.key,
        entry.value as Map<String, dynamic>,
      );
    }

    final defaultId = json["default"] as String? ?? "dev";
    final stored    = prefs.getString( _prefsKey );
    final active    = _parseContext( stored ?? defaultId ) ?? ServerContext.dev;

    final service = ServerContextService._( prefs, contexts, active );
    service._applyToAppConstants();
    return service;
  }

  void _applyToAppConstants() {
    AppConstants.apiBaseUrl = activeConfig.baseUrl;
    AppConstants.wsBaseUrl  = activeConfig.wsUrl;
  }

  ServerContext get active => _active;
  ServerContextConfig get activeConfig => _contexts[ _active ]!;
  String get baseUrl => activeConfig.baseUrl;
  String get wsUrl   => activeConfig.wsUrl;

  ServerContextConfig configFor( ServerContext ctx ) => _contexts[ ctx ]!;
  List<ServerContextConfig> get all => _contexts.values.toList();

  /// Switch the active context. Callers are responsible for invoking any
  /// logout / session-clear hooks before or after this call; this service
  /// only mutates the stored URL selection.
  Future<void> setActive( ServerContext ctx ) async {
    if ( ctx == _active ) return;
    _active = ctx;
    _applyToAppConstants();
    await _prefs.setString( _prefsKey, _idOf( ctx ) );
  }

  static ServerContext? _parseContext( String? id ) {
    switch ( id ) {
      case "dev":  return ServerContext.dev;
      case "test": return ServerContext.test;
      default:     return null;
    }
  }

  static String _idOf( ServerContext ctx ) {
    switch ( ctx ) {
      case ServerContext.dev:  return "dev";
      case ServerContext.test: return "test";
    }
  }
}
