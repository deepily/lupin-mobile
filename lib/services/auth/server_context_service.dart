import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';

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

/// Resolves the active server context and exposes its base URL + WS URL.
///
/// A context is identified by its key in `server-contexts.json` ("dev",
/// "test", "lan-dev", "lan-test", ...), so adding a server is a JSON edit
/// only. Persists the user's last selection via SharedPreferences
/// (non-secret; URLs are not sensitive).
class ServerContextService {
  static const String _assetPath    = "assets/config/server-contexts.json";
  static const String _prefsKey     = "active_server_context";

  final SharedPreferences _prefs;
  final Map<String, ServerContextConfig> _contexts;
  String _active;

  ServerContextService._( this._prefs, this._contexts, this._active );

  /// Load the bundled config and resolve the previously-selected context
  /// (or the file's declared default on first launch). A stored id that is
  /// no longer in the JSON falls back to the default.
  static Future<ServerContextService> load( SharedPreferences prefs ) async {
    final raw  = await rootBundle.loadString( _assetPath );
    final json = jsonDecode( raw ) as Map<String, dynamic>;

    final contextsJson = json["contexts"] as Map<String, dynamic>;
    final contexts     = <String, ServerContextConfig>{};
    for ( final entry in contextsJson.entries ) {
      contexts[ entry.key ] = ServerContextConfig.fromJson(
        entry.key,
        entry.value as Map<String, dynamic>,
      );
    }

    final declared  = json["default"] as String? ?? "dev";
    final defaultId = contexts.containsKey( declared ) ? declared : contexts.keys.first;
    final stored    = prefs.getString( _prefsKey );
    final active    = ( stored != null && contexts.containsKey( stored ) ) ? stored : defaultId;

    final service = ServerContextService._( prefs, contexts, active );
    service._applyToAppConstants();
    return service;
  }

  void _applyToAppConstants() {
    AppConstants.apiBaseUrl = activeConfig.baseUrl;
    AppConstants.wsBaseUrl  = activeConfig.wsUrl;
  }

  /// Id of the active context (its key in the JSON).
  String get active => _active;
  ServerContextConfig get activeConfig => _contexts[ _active ]!;
  String get baseUrl => activeConfig.baseUrl;
  String get wsUrl   => activeConfig.wsUrl;

  ServerContextConfig configFor( String id ) => _contexts[ id ]!;

  /// Every context in the JSON, in file order.
  List<ServerContextConfig> get all => _contexts.values.toList();

  final List<void Function( ServerContextConfig )> _listeners = [];

  /// Register [listener] to run, synchronously, every time [setActive]
  /// switches to a different context. Anything that captured a base URL at
  /// start-up (the shared Dio's `options.baseUrl`, a screen showing the
  /// active server) must follow the switch through here, or its requests
  /// keep going to the old host while AppConstants readers use the new one.
  void addListener( void Function( ServerContextConfig ) listener ) => _listeners.add( listener );

  void removeListener( void Function( ServerContextConfig ) listener ) => _listeners.remove( listener );

  /// Switch the active context: updates AppConstants, notifies listeners,
  /// and persists the choice. Callers are responsible for clearing the OLD
  /// context's session BEFORE calling this (see AuthBloc's
  /// AuthServerContextSwitchRequested); this service only owns the URL
  /// selection.
  ///
  /// Requires:
  ///   - [id] is a context key in server-contexts.json
  ///
  /// Ensures:
  ///   - AppConstants URLs and every listener see the new context before the
  ///     returned future's first await
  ///   - a no-op (no listener calls) when [id] is already active
  ///
  /// Raises:
  ///   - ArgumentError if [id] is not a context in the JSON
  Future<void> setActive( String id ) async {
    if ( !_contexts.containsKey( id ) ) {
      throw ArgumentError.value( id, "id", "unknown server context" );
    }
    if ( id == _active ) return;
    _active = id;
    _applyToAppConstants();
    for ( final listener in List.of( _listeners ) ) {
      listener( activeConfig );
    }
    await _prefs.setString( _prefsKey, id );
  }
}
