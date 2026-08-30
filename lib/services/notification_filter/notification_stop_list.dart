import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One user-editable stop-list entry: a case-insensitive PREFIX matched
/// against a notification's trimmed `message`. Checked (`enabled`) means
/// the message is neither rendered nor spoken (Rick 2026-08-21: "one
/// checkbox = hide + mute").
@immutable
class StopPattern {
  final String pattern;
  final bool   enabled;

  const StopPattern( { required this.pattern, this.enabled = true } );

  StopPattern copyWith( { String? pattern, bool? enabled } ) =>
      StopPattern( pattern: pattern ?? this.pattern, enabled: enabled ?? this.enabled );

  Map<String, dynamic> toJson() => { 'pattern': pattern, 'enabled': enabled };

  factory StopPattern.fromJson( Map<String, dynamic> j ) => StopPattern(
    pattern : ( j[ 'pattern' ] ?? '' ).toString(),
    enabled : j[ 'enabled' ] != false,
  );

  @override
  bool operator ==( Object other ) => other is StopPattern && other.pattern == pattern && other.enabled == enabled;
  @override
  int get hashCode => Object.hash( pattern, enabled );
  @override
  String toString() => 'StopPattern($pattern, ${enabled ? "on" : "off"})';
}

/// The notification stop-list (plan 2026.08.21 §3): an ordered list of
/// [StopPattern]s persisted as JSON under [prefsKey]. ONE predicate,
/// [matches], applied at three seams — focus ingest/backfill
/// (`FocusChatBloc`), the conversation list (`ConversationScreen`) and the
/// TTS gate (`TtsOrchestrator`) — so "hidden" means hidden everywhere.
///
/// Seeds target the Claude Code tool-call chatter emitted by
/// `post_tool_use.py` (`"Done: <tool>"`), which the browser collapses into
/// one DOM node and the phone cannot.
class NotificationStopList extends ChangeNotifier {
  static const String prefsKey         = 'notif_filter.stop_list';
  /// Plan 2026.08.21 §4 — collapse consecutive same-`progress_group_id`
  /// messages into one expandable row. Default ON (browser parity).
  static const String collapseGroupsKey = 'notif_filter.collapse_groups';

  static const List<String> defaultPatterns = [
    'Done: mcp',
    'Done: Bash',
    'Done: ToolSearch',
    'Done: Read',
    'Done: Edit',
    'Done: Write',
    'Done: Grep',
    'Done: Glob',
  ];

  final SharedPreferences _prefs;
  List<StopPattern>       _patterns;

  NotificationStopList( this._prefs ) : _patterns = const [] {
    _patterns = _load() ?? _seeded();
  }

  static List<StopPattern> _seeded() =>
      defaultPatterns.map( ( p ) => StopPattern( pattern: p ) ).toList();

  List<StopPattern>? _load() {
    final raw = _prefs.getString( prefsKey );
    if ( raw == null ) return null;
    try {
      final decoded = jsonDecode( raw );
      if ( decoded is! List ) return null;
      return decoded
          .whereType<Map>()
          .map( ( m ) => StopPattern.fromJson( Map<String, dynamic>.from( m ) ) )
          .where( ( p ) => p.pattern.trim().isNotEmpty )
          .toList();
    } on FormatException {
      return null;   // corrupt value ⇒ fall back to seeds (never crash the app over a pref)
    }
  }

  Future<void> _persist() async {
    await _prefs.setString( prefsKey, jsonEncode( _patterns.map( ( p ) => p.toJson() ).toList() ) );
  }

  /// Read-only view, in display order.
  List<StopPattern> get patterns => List.unmodifiable( _patterns );

  bool get collapseGroups => _prefs.getBool( collapseGroupsKey ) ?? true;

  Future<void> setCollapseGroups( bool v ) async {
    await _prefs.setBool( collapseGroupsKey, v );
    notifyListeners();
  }

  /// Enabled patterns only (the ones that actually suppress).
  Iterable<StopPattern> get active => _patterns.where( ( p ) => p.enabled );

  /// THE predicate: true when [message] starts with any enabled pattern,
  /// case-insensitively, after trimming both. Null/blank never matches.
  bool matches( String? message ) => matchFor( message ) != null;

  /// WHICH rule matched, not merely THAT one did (AC-S3.7, plan
  /// 2026.08.29 §6). A suppressed answer or question is rendered with the
  /// rule named — "not spoken: matches 'Done: Bash'" — so suppression is
  /// visible rather than indistinguishable from a hang. Returns the FIRST
  /// enabled pattern [message] starts with, in display order, else null.
  ///
  /// [matches] delegates here so the two can never disagree: one scan, one
  /// answer, and the boolean is a projection of the rule.
  StopPattern? matchFor( String? message ) {
    if ( message == null ) return null;
    final m = message.trim().toLowerCase();
    if ( m.isEmpty ) return null;
    for ( final p in _patterns ) {
      if ( !p.enabled ) continue;
      final needle = p.pattern.trim().toLowerCase();
      if ( needle.isNotEmpty && m.startsWith( needle ) ) return p;
    }
    return null;
  }

  Future<void> setEnabled( int index, bool enabled ) async {
    if ( index < 0 || index >= _patterns.length ) return;
    _patterns = List.of( _patterns )..[ index ] = _patterns[ index ].copyWith( enabled: enabled );
    notifyListeners();
    await _persist();
  }

  /// Append a new enabled pattern; blank or duplicate (case-insensitive)
  /// input is ignored and returns false.
  Future<bool> add( String pattern ) async {
    final p = pattern.trim();
    if ( p.isEmpty ) return false;
    if ( _patterns.any( ( e ) => e.pattern.toLowerCase() == p.toLowerCase() ) ) return false;
    _patterns = List.of( _patterns )..add( StopPattern( pattern: p ) );
    notifyListeners();
    await _persist();
    return true;
  }

  Future<void> removeAt( int index ) async {
    if ( index < 0 || index >= _patterns.length ) return;
    _patterns = List.of( _patterns )..removeAt( index );
    notifyListeners();
    await _persist();
  }

  Future<void> resetToDefaults() async {
    _patterns = _seeded();
    notifyListeners();
    await _persist();
  }
}
