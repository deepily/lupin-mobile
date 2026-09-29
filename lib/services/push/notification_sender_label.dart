/// WHO a wake notification is from, as one short line for its title
/// (row d9bc6f6c; Tiffany's ruling, 2026-09-28 20:16Z).
///
/// The problem this solves is the lock screen, not the app: a notification that
/// arrives with the phone face down says what happened but not who said it, so
/// the only way to find out is to open the app and start tabbing. The title is
/// the one field a user reads before deciding whether to look at all.
///
/// The ruled mapping, in order:
///   1. a voice persona          → "🌻 Maya"      (icon + name)
///   2. no persona, a sender id  → "lupin-mobile" (the PROJECT, and only that)
///   3. neither                  → "Lupin"
///
/// ⚠️ THE HASH IS DELIBERATELY DROPPED IN CASE 2. A sender id is
/// `claude.code@lupin-mobile.deepily.ai#a1b2c3d4`, and the `#a1b2c3d4` is how the
/// fleet tells two seats of one project apart — but it is eight hex characters,
/// which nobody reads off a lock screen. Tiffany's call, in as many words: Rick
/// cannot read a hash. So the project alone, even though that makes two seats of
/// the same project indistinguishable in the title. The conversation the tap
/// opens is keyed by the FULL sender id from the payload, so nothing about the
/// routing depends on this string.
library;

/// Build the notification title for [item], the server's `notification` object.
///
/// Requires:
///   - item is the `/next` notification map, or null
///
/// Ensures:
///   - returns a non-empty string, always — [fallback] when nothing identifies
///     the sender, so a title is never blank
///   - a persona's icon is included only when it has one; a persona with a name
///     and no glyph yields just the name
///   - never throws, for any shape of input
String notificationSenderLabel(
  Map<String, dynamic>? item, {
  String fallback = 'Lupin',
} ) {
  if ( item == null ) return fallback;

  final persona = _personaOf( item );
  if ( persona != null ) return persona;

  final project = projectOfSenderId( item[ 'sender_id' ]?.toString() );
  if ( project != null ) return project;

  return fallback;
}

/// "🌻 Maya", "Maya", or null when the item carries no usable persona.
String? _personaOf( Map<String, dynamic> item ) {
  final raw = item[ 'voice_persona' ];
  if ( raw is! Map ) return null;

  // `display_name` first: it is what the persona is CALLED, and `name` is the
  // allocation key — they agree today and there is no reason to prefer the key.
  final name = ( raw[ 'display_name' ] ?? raw[ 'name' ] )?.toString().trim() ?? '';
  if ( name.isEmpty ) return null;

  final icon = raw[ 'icon' ]?.toString().trim() ?? '';
  return icon.isEmpty ? name : '$icon $name';
}

/// The project segment of a Claude Code sender id, or null.
///
/// `claude.code@lupin-mobile.deepily.ai#a1b2c3d4` → `lupin-mobile`.
///
/// Ensures:
///   - null for null, for a string with no `@`, and for anything that leaves an
///     empty project once the host and the `#hash` are stripped
///   - the `#hash` suffix is removed whether or not it is present
///   - never throws
String? projectOfSenderId( String? senderId ) {
  if ( senderId == null ) return null;

  final at = senderId.lastIndexOf( '@' );
  if ( at < 0 || at == senderId.length - 1 ) return null;

  var host = senderId.substring( at + 1 );

  // Strip the session hash: it is not part of the host, and leaving it on would
  // put `deepily.ai#a1b2c3d4` in the title for a hostless id.
  final hash = host.indexOf( '#' );
  if ( hash >= 0 ) host = host.substring( 0, hash );

  final project = host.split( '.' ).first.trim();
  return project.isEmpty ? null : project;
}
