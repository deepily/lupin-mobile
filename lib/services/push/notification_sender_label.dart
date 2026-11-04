/// Who a wake notification is from, as one short line for its title.
///
/// The problem is the lock screen, not the app. A notification that arrives with the phone face down says
/// what happened but not who said it. The only way to find out is to open the app and start tabbing.
/// The title is the one field a user reads before deciding whether to look at all.
/// Design: src/docs/decisions/README.md (R-PUSH-sender-label)
///
/// The mapping, in order:
///   1. a voice persona is shown as icon and name, for example "🌻 Maya"
///   2. no persona and a sender id is shown as the project only, for example "lupin-mobile"
///   3. neither is shown as "Lupin"
///
/// The hash is dropped in case 2. A sender id looks like `claude.code@lupin-mobile.deepily.ai#<8 hex characters>`.
/// The hash tells two seats of one project apart, but nobody reads eight hex characters off a lock screen.
/// The project alone is shown, even though two seats of one project then look the same in the title.
/// The conversation the tap opens is keyed by the full sender id from the payload, so routing does not use this string.
library;

/// Builds the notification title for [item], the server's `notification` object.
///
/// Requires:
///   - item is the `/next` notification map, or null
///
/// Ensures:
///   - returns a non-empty string: [fallback] when nothing identifies the sender, so a title is never blank
///   - a persona's icon is included only when it has one; a persona with a name and no glyph yields the name
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

/// Returns "🌻 Maya", "Maya", or null when the item carries no usable persona.
String? _personaOf( Map<String, dynamic> item ) {
  final raw = item[ 'voice_persona' ];
  if ( raw is! Map ) return null;

  // Prefer `display_name`: it is what the persona is called, and `name` is the allocation key.
  // They agree today and there is no reason to prefer the key.
  final name = ( raw[ 'display_name' ] ?? raw[ 'name' ] )?.toString().trim() ?? '';
  if ( name.isEmpty ) return null;

  final icon = raw[ 'icon' ]?.toString().trim() ?? '';
  return icon.isEmpty ? name : '$icon $name';
}

/// The project segment of a Claude Code sender id, or null.
///
/// `claude.code@lupin-mobile.deepily.ai#<hash>` gives `lupin-mobile`.
///
/// Ensures:
///   - null for null, for a string with no `@`, and for anything that leaves an empty project once the host
///     and the `#hash` are stripped
///   - the `#hash` suffix is removed whether or not it is present
///   - never throws
String? projectOfSenderId( String? senderId ) {
  if ( senderId == null ) return null;

  final at = senderId.lastIndexOf( '@' );
  if ( at < 0 || at == senderId.length - 1 ) return null;

  var host = senderId.substring( at + 1 );

  // Strip the session hash. It is not part of the host, and leaving it on would put
  // a `#hash` suffix in the title for a hostless id.
  final hash = host.indexOf( '#' );
  if ( hash >= 0 ) host = host.substring( 0, hash );

  final project = host.split( '.' ).first.trim();
  return project.isEmpty ? null : project;
}

/// The key a sender mute is stored under for [item]'s sender.
///
/// It is not the label and not the session: `sender_id` carries a `#hash` that changes when a persona re-spins.
/// A mute keyed on it would lapse when the seat it silenced was replaced, so "Mute Maya" would stop meaning Maya.
/// Design: src/docs/decisions/README.md (R-NA-mute-quiet)
///
/// Requires:
///   - item is a server `notification` map, or null
///
/// Ensures:
///   - a voice persona gives `persona:maya`, the allocation `name` lower-cased with accents folded
///   - otherwise a sender id gives `project:lupin-mobile`, the project [projectOfSenderId] titles
///   - otherwise a raw sender id gives `sender:<raw sender_id>`
///   - the same sender always yields the same key, across sessions and re-spins
///   - null only when the item identifies no sender at all, so there is nothing to mute
///   - never throws
String? notificationSenderKey( Map<String, dynamic>? item ) {
  if ( item == null ) return null;

  final raw = item[ 'voice_persona' ];
  if ( raw is Map ) {
    // Use `name` here, not `display_name`. The allocation key is the stable one, and a display name
    // is free to gain a flourish without un-muting anybody.
    final name = foldSenderName( ( raw[ 'name' ] ?? raw[ 'display_name' ] )?.toString() ?? '' );
    if ( name.isNotEmpty ) return 'persona:$name';
  }

  final senderId = item[ 'sender_id' ]?.toString().trim() ?? '';
  final project  = projectOfSenderId( senderId );
  if ( project != null ) return 'project:$project';

  return senderId.isEmpty ? null : 'sender:$senderId';
}

/// Lower-cases [name] and folds the accents persona names carry.
///
/// "María" and "maria" are therefore one sender. The fold matches the one the server uses for DM recipients.
///
/// Ensures:
///   - trimmed and lower-cased, with a, e, i, o, u, u-umlaut and n-tilde (and their grave and circumflex forms) folded
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
