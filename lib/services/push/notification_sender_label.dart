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

/// The key a MUTE is stored under for [item]'s sender (row f1e80e67, plan §7.3).
///
/// Not the label and not the session: `sender_id` carries a `#hash` that changes
/// every time a persona re-spins, so a mute keyed on it would quietly lapse the
/// moment the seat it silenced was replaced. "Mute Maya" has to still mean Maya
/// an hour later. So, in order:
///   1. a voice persona  → `persona:maya`  (allocation `name`, lower-cased, accents folded)
///   2. a sender id      → `project:lupin-mobile`  (the same project [projectOfSenderId] titles)
///   3. anything else    → `sender:<raw sender_id>`, or null when there is none
///
/// Requires:
///   - item is a server `notification` map, or null
///
/// Ensures:
///   - the same sender always yields the same key, across sessions and re-spins
///   - null only when the item identifies no sender at all (nothing to mute)
///   - never throws
String? notificationSenderKey( Map<String, dynamic>? item ) {
  if ( item == null ) return null;

  final raw = item[ 'voice_persona' ];
  if ( raw is Map ) {
    // `name` here, NOT `display_name`: the allocation key is the stable one, and
    // a display name is free to gain a flourish without un-muting anybody.
    final name = foldSenderName( ( raw[ 'name' ] ?? raw[ 'display_name' ] )?.toString() ?? '' );
    if ( name.isNotEmpty ) return 'persona:$name';
  }

  final senderId = item[ 'sender_id' ]?.toString().trim() ?? '';
  final project  = projectOfSenderId( senderId );
  if ( project != null ) return 'project:$project';

  return senderId.isEmpty ? null : 'sender:$senderId';
}

/// Lower-case [name] and fold the accents persona names actually carry, so
/// "María" and "maria" are one sender. Same fold the server uses for DM recipients.
///
/// Ensures:
///   - trimmed, lower-cased, with á é í ó ú ü ñ (and their grave/circumflex kin) folded
///   - never throws
String foldSenderName( String name ) {
  const folds = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
    'ñ': 'n', 'ç': 'c',
  };
  final lower = name.trim().toLowerCase();
  final out   = StringBuffer();
  for ( final ch in lower.split( '' ) ) {
    out.write( folds[ ch ] ?? ch );
  }
  return out.toString();
}
