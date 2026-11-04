import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One user-editable stop-list entry: a case-insensitive prefix of a trimmed `message`.
///
/// A checked entry (`enabled`) hides the message and mutes it, with one checkbox for both.
/// Design: src/docs/decisions/README.md (R-NF-one-checkbox)
@immutable
class StopPattern {
  /// Text a message must start with, compared case-insensitively.
  final String pattern;
  /// Whether this entry suppresses messages.
  final bool   enabled;

  /// Creates an entry that is enabled unless [enabled] is false.
  const StopPattern( { required this.pattern, this.enabled = true } );

  /// Copy with the given fields replaced.
  StopPattern copyWith( { String? pattern, bool? enabled } ) =>
      StopPattern( pattern: pattern ?? this.pattern, enabled: enabled ?? this.enabled );

  /// Serializes with `pattern` and `enabled` keys.
  Map<String, dynamic> toJson() => { 'pattern': pattern, 'enabled': enabled };

  /// Reads an entry from JSON; a missing pattern is empty and a missing `enabled` is true.
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

/// Ordered [StopPattern]s that hide and mute matching notifications, persisted as JSON.
///
/// One predicate, [matches], is applied in three places, so a hidden message is hidden everywhere.
/// They are focus ingest and backfill (`FocusChatBloc`), the conversation list
/// (`ConversationScreen`) and the TTS gate (`TtsOrchestrator`). The seeds target the tool-call chatter `post_tool_use.py` emits
/// (`"Done: <tool>"`), which the browser collapses into one node and the phone cannot.
class NotificationStopList extends ChangeNotifier {
  /// Preference key holding the pattern list as JSON.
  static const String prefsKey         = 'notif_filter.stop_list';
  /// Preference key for collapsing same-`progress_group_id` messages into one row.
  ///
  /// The default is on, to match the browser.
  static const String collapseGroupsKey = 'notif_filter.collapse_groups';

  /// Patterns seeded when nothing is stored.
  ///
  /// Each is `Done:` followed by mcp, Bash, ToolSearch, Read, Edit, Write, Grep or Glob.
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

  /// Loads the stored list, falling back to [defaultPatterns] when nothing usable is stored.
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

  /// Read-only view of the patterns, in display order.
  List<StopPattern> get patterns => List.unmodifiable( _patterns );

  /// Whether consecutive same-group messages collapse; true when unset.
  bool get collapseGroups => _prefs.getBool( collapseGroupsKey ) ?? true;

  /// Stores the collapse preference and notifies listeners.
  Future<void> setCollapseGroups( bool v ) async {
    await _prefs.setBool( collapseGroupsKey, v );
    notifyListeners();
  }

  /// The enabled patterns, which are the ones that suppress.
  Iterable<StopPattern> get active => _patterns.where( ( p ) => p.enabled );

  /// True when [message] starts with any enabled pattern; null or blank never matches.
  ///
  /// Both sides are trimmed and compared case-insensitively.
  bool matches( String? message ) => matchFor( message ) != null;

  /// The first enabled pattern that [message] starts with, in display order, or null.
  ///
  /// The caller can name the rule that suppressed a message, for example
  /// "not spoken: matches 'Done: Bash'". That way a suppressed answer or question is not mistaken
  /// for a hang. [matches] delegates here, so the two cannot disagree.
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

  /// Checks or unchecks the entry at [index]; an out-of-range index is ignored.
  Future<void> setEnabled( int index, bool enabled ) async {
    if ( index < 0 || index >= _patterns.length ) return;
    _patterns = List.of( _patterns )..[ index ] = _patterns[ index ].copyWith( enabled: enabled );
    notifyListeners();
    await _persist();
  }

  /// Appends an enabled pattern and returns true.
  ///
  /// Returns false, changing nothing, when [pattern] is blank or already present, ignoring case.
  Future<bool> add( String pattern ) async {
    final p = pattern.trim();
    if ( p.isEmpty ) return false;
    if ( _patterns.any( ( e ) => e.pattern.toLowerCase() == p.toLowerCase() ) ) return false;
    _patterns = List.of( _patterns )..add( StopPattern( pattern: p ) );
    notifyListeners();
    await _persist();
    return true;
  }

  /// Replaces the text at [index], keeping its checked state and position.
  ///
  /// Returns false and leaves the list unchanged when the new text is blank or another row already has it,
  /// ignoring case. Saving a row's own current text succeeds as a no-op.
  /// Design: src/docs/decisions/README.md (R-NF-edit-no-duplicate)
  ///
  /// Ensures:
  ///   - this call never creates a duplicate, but [_load] still reads duplicates saved by an older build
  Future<bool> editAt( int index, String pattern ) async {
    if ( index < 0 || index >= _patterns.length ) return false;
    final p = pattern.trim();
    if ( p.isEmpty ) return false;
    final lower = p.toLowerCase();
    for ( var i = 0; i < _patterns.length; i++ ) {
      if ( i != index && _patterns[ i ].pattern.toLowerCase() == lower ) return false;
    }
    _patterns = List.of( _patterns )..[ index ] = _patterns[ index ].copyWith( pattern: p );
    notifyListeners();
    await _persist();
    return true;
  }

  /// Puts [entry] back at [index], the undo half of a delete.
  ///
  /// It takes a whole [StopPattern], not a string. Undoing through [add] would append at the end
  /// and force
  /// `enabled: true`, losing the position and checked state. An out-of-range index is ignored, not clamped,
  /// so a stale undo cannot land somewhere else.
  Future<void> insertAt( int index, StopPattern entry ) async {
    if ( index < 0 || index > _patterns.length ) return;
    if ( entry.pattern.trim().isEmpty ) return;
    _patterns = List.of( _patterns )..insert( index, entry );
    notifyListeners();
    await _persist();
  }

  /// Removes the entry at [index]; an out-of-range index is ignored.
  Future<void> removeAt( int index ) async {
    if ( index < 0 || index >= _patterns.length ) return;
    _patterns = List.of( _patterns )..removeAt( index );
    notifyListeners();
    await _persist();
  }

  /// Replaces the list with [defaultPatterns].
  Future<void> resetToDefaults() async {
    _patterns = _seeded();
    notifyListeners();
    await _persist();
  }
}
