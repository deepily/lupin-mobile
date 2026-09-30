/// Voice/persona allocated to a Claude Code session — mirrors the server's
/// per-session persona bridge schema. See parent design at
/// `<parent-lupin>/src/rnd/v0.1.7/2026.04.28-per-session-voice-personas/01-design.md`
/// and the mobile port plan at
/// `<mobile>/src/rnd/v0.1.7/2026.05.06-mobile-port-plans/voice-persona/`.
///
/// Per `Q1` (server stamps persona on every notification) and `Q7` (liberal
/// `fromJson` — no enum validation), this model is a passive carrier. Fields
/// default to null on missing/malformed input; consumers null-check before
/// use and degrade gracefully to no-persona behavior so server-stamp absence
/// flows cleanly to Sam fallback per `Q3`.
library;

DateTime? _parseDt( dynamic v ) =>
    v == null ? null : DateTime.tryParse( v.toString() );

String? _asStr( dynamic v ) => v is String ? v : null;

/// Per-session voice/persona allocation. All string fields are nullable to
/// honor the null-defense contract — a partial server response (or future
/// schema additions) must NOT throw at parse time.
class VoicePersona {
  final String?   name;
  final String?   voiceId;
  final String?   icon;
  final String?   color;
  final bool      borrowed;
  final bool      overflow;
  final DateTime? assignedAt;
  final String?   displayName;

  const VoicePersona( {
    this.name,
    this.voiceId,
    this.icon,
    this.color,
    this.borrowed = false,
    this.overflow = false,
    this.assignedAt,
    this.displayName,
  } );

  /// Liberal parser per `Q7` — accepts any string fields; missing fields
  /// default to null; `borrowed` and `overflow` default to false; never
  /// throws on shape. `assigned_at` is parsed via `DateTime.tryParse` so a
  /// malformed timestamp becomes null rather than blowing up the envelope.
  ///
  /// `overflow=true` indicates the server allocated Sam (system-default
  /// voice) because the main pool was exhausted at allocate time. Distinct
  /// from `borrowed=true` (legacy hash-borrow fallback used only when Sam is
  /// unconfigured). UI renders the two states with different badge styling.
  /// See: parent-lupin/src/rnd/v0.1.7/2026.05.16-voice-persona-stale-bridge-and-sam-overflow.md
  factory VoicePersona.fromJson( Map<String, dynamic> json ) {
    return VoicePersona(
      name        : _asStr( json["name"] ),
      voiceId     : _asStr( json["voice_id"] ),
      icon        : _asStr( json["icon"] ),
      color       : _asStr( json["color"] ),
      borrowed    : json["borrowed"] == true,
      overflow    : json["overflow"] == true,
      assignedAt  : _parseDt( json["assigned_at"] ),
      displayName : _asStr( json["display_name"] ),
    );
  }

  /// Round-trip helper for fixture-backed tests. Emits the same key-shape the
  /// server bridge writes; null fields are still emitted (as null) so a
  /// downstream `fromJson` round-trip preserves the absence-vs-presence
  /// distinction.
  Map<String, dynamic> toJson() => {
    "name"         : name,
    "voice_id"     : voiceId,
    "icon"         : icon,
    "color"        : color,
    "borrowed"     : borrowed,
    "overflow"     : overflow,
    "assigned_at"  : assignedAt?.toIso8601String(),
    "display_name" : displayName,
  };

  /// Equality keyed on `voiceId` per `Q3`-driven contract: TTS dispatch
  /// targets the voice, not the session-instance. Two same-voice-different-
  /// session personas compare equal — acceptable because we look up
  /// persona-by-session via `senderId` in the bloc state map, never by
  /// persona identity.
  @override
  bool operator ==( Object other ) =>
      identical( this, other ) ||
      ( other is VoicePersona && other.voiceId == voiceId );

  @override
  int get hashCode => voiceId.hashCode;

  @override
  String toString() =>
      "VoicePersona(name: $name, voiceId: $voiceId, borrowed: $borrowed, overflow: $overflow)";
}
