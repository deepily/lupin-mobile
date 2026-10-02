/// Voice and persona allocated to a Claude Code session, as the server stamps it.
///
/// A passive carrier: parsing accepts any strings and never validates against an enum.
/// Consumers null-check each field and fall back to the default voice when it is absent.
/// Design: `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/voice-persona/`
library;

DateTime? _parseDt( dynamic v ) =>
    v == null ? null : DateTime.tryParse( v.toString() );

String? _asStr( dynamic v ) => v is String ? v : null;

/// Per-session voice and persona allocation.
///
/// Every string field is nullable so a partial server response never throws at parse time.
class VoicePersona {
  /// Persona name, such as the seat's short first name.
  final String?   name;

  /// Identifier of the TTS voice assigned to the session.
  final String?   voiceId;

  /// Icon the UI shows beside the persona.
  final String?   icon;

  /// Badge color supplied by the server.
  final String?   color;

  /// True when the voice came from the hash-borrow fallback.
  ///
  /// The server uses that fallback only when no default voice is configured.
  final bool      borrowed;

  /// True when the server gave the session the default voice because the main pool was full.
  final bool      overflow;

  /// When the server allocated the persona, or null when absent or malformed.
  final DateTime? assignedAt;

  /// Human-readable persona label.
  final String?   displayName;

  /// Builds a persona from already-parsed fields.
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

  /// Parses a persona from JSON without ever throwing on shape.
  ///
  /// Missing fields become null, `borrowed` and `overflow` default to false,
  /// and a malformed `assigned_at` becomes null.
  /// The UI styles `overflow` and `borrowed` badges differently.
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

  /// Emits the key shape the server bridge writes, including null fields.
  ///
  /// Keeping nulls lets a `fromJson` round trip preserve absent versus present.
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

  /// Two personas are equal when their `voiceId` matches.
  ///
  /// TTS dispatch targets the voice, not the session. Persona lookup goes
  /// through `senderId` in the bloc state map, never through persona identity.
  @override
  bool operator ==( Object other ) =>
      identical( this, other ) ||
      ( other is VoicePersona && other.voiceId == voiceId );

  /// Hash derived from `voiceId`, matching `==`.
  @override
  int get hashCode => voiceId.hashCode;

  /// Debug string with the identifying fields.
  @override
  String toString() =>
      "VoicePersona(name: $name, voiceId: $voiceId, borrowed: $borrowed, overflow: $overflow)";
}
