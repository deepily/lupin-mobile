/// Look up ONE ticket by the hash people actually paste (walk-through item M3).
///
/// A port of the web's `shared/task-lookup.js`, which both web clients read. Rick,
/// 2026-09-09: *"Every time someone refers to a row for a ticket by # I have no idea what
/// they're talking about."*
///
/// 🔴 IT MUST HIT `GET /api/tasks/<ref>`, NEVER `GET /api/tasks?id_prefix=<ref>`. The
/// query form is the BOARD query and chains the owed filter after the prefix match, so it
/// hides holding-area rows — measured on the web, 1 of 23 held rows was findable that
/// way. The single-row endpoint applies no visibility filter, and the hashes Rick is
/// handed are usually for rows that are NOT on his board.
///
/// ⚠️ THE CLASSIFIER MIRRORS `task_store_rules.classify_task_ref` ON THE SERVER, which
/// is what actually governs. This copy exists so the box refuses junk without a round
/// trip and says why. The web pins its copy to the Python constant with a test; this one
/// is pinned to the same numbers by `task_lookup_test.dart`.
library;

/// The shortest prefix the server will resolve.
const minTaskRefPrefixLen = 4;

enum TaskRefKind { full, prefix, invalid }

/// A classified reference. [value] is null exactly when [kind] is invalid.
class TaskRef {
  final TaskRefKind kind;
  final String? value;

  const TaskRef( this.kind, this.value );
}

final _canonicalUuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
final _hexOnly = RegExp( r'^[0-9a-f]+$' );
const _compactUuidLen = 32;

/// Classify what the user typed. Pure; never throws.
///
/// Requires:
///   - [ref] is the raw text from the box; null is allowed
///
/// Ensures:
///   - a canonical UUID, or 32 bare hex chars -> full, lowercased
///   - >= [minTaskRefPrefixLen] hex chars, hyphens tolerated -> prefix, hyphens stripped
///   - anything else -> invalid, with a null value
///   - junk never classifies as a prefix: a lookup built from arbitrary text is a search
///     box, which is a different feature
TaskRef classifyTaskRef( String? ref ) {
  if ( ref == null ) return const TaskRef( TaskRefKind.invalid, null );

  final candidate = ref.trim().toLowerCase();
  if ( candidate.isEmpty ) return const TaskRef( TaskRefKind.invalid, null );

  if ( _canonicalUuid.hasMatch( candidate ) ) return TaskRef( TaskRefKind.full, candidate );

  final compact = candidate.replaceAll( '-', '' );
  if ( !_hexOnly.hasMatch( compact ) ) return const TaskRef( TaskRefKind.invalid, null );
  if ( compact.length == _compactUuidLen ) return TaskRef( TaskRefKind.full, compact );
  if ( compact.length >= minTaskRefPrefixLen ) return TaskRef( TaskRefKind.prefix, compact );

  return const TaskRef( TaskRefKind.invalid, null );
}

/// The lookup path for a reference, or null when it is not one.
///
/// Ensures:
///   - a classifiable ref -> `/api/tasks/<normalized>`, so two spellings of one id
///     produce one URL
///   - junk -> null, so the box can refuse it without spending a round trip on a 422
String? taskLookupPath( String? ref ) {
  final classified = classifyTaskRef( ref );
  if ( classified.kind == TaskRefKind.invalid ) return null;
  return '/api/tasks/${Uri.encodeComponent( classified.value! )}';
}

/// Shown when the typed text will not classify. Worded as the web words it.
const taskRefRefusalMessage =
    'Enter at least $minTaskRefPrefixLen hex characters of a ticket id (0-9, a-f). '
    'Hyphens are fine — paste as much of the id as you have.';

/// Shown on a 401. The web says "refresh the page"; a phone has no page to refresh.
const taskLookupAuthRequiredMessage = 'Signed out — sign back in to look up tickets.';

/// Shown when the store did not answer.
///
/// ⚠️ THE SERVER'S OWN TEXT IS DELIBERATELY NOT PASSED THROUGH on this arm, as on the
/// web: a 5xx's message is "HTTP 500" or a stack fragment, which the reader cannot act on.
const taskLookupUnreachableMessage = 'The store did not answer. Try again in a moment.';

/// A lookup the server answered with something other than a row.
class TaskLookupException implements Exception {
  /// The HTTP status, or 0 when there was no response at all.
  final int status;

  /// FastAPI's `detail`, when the server sent one.
  final String? detail;

  const TaskLookupException( this.status, { this.detail } );

  @override
  String toString() => 'TaskLookupException($status, $detail)';
}

/// What the box says when a lookup failed.
///
/// Ensures:
///   - 404 -> names what was typed, so a typo is visible
///   - 422 -> the server's `detail` passes through, because for an ambiguous prefix it
///     NAMES the candidate ids and is the most useful text on the screen
///   - 401 -> the sign-in sentence
///   - anything else -> the unreachable sentence
String describeLookupFailure( String typed, TaskLookupException error ) {
  switch ( error.status ) {
    case 404 : return 'No ticket matches "$typed".';
    case 422 : return error.detail ?? '"$typed" is not a usable ticket reference.';
    case 401 : return taskLookupAuthRequiredMessage;
    default  : return taskLookupUnreachableMessage;
  }
}
