/// Looks up one ticket by the hash people paste.
///
/// This ports the web's `shared/task-lookup.js`, which both web clients read. It must hit
/// `GET /api/tasks/<ref>`, never `GET /api/tasks?id_prefix=<ref>`. The query form is the
/// board query and chains the owed filter after the prefix match. It therefore hides
/// holding-area rows, and on the web 1 of 23 held rows was findable that way. The
/// single-row endpoint applies no visibility filter. The hashes people paste are usually
/// for rows that are not on the board.
///
/// The classifier mirrors `task_store_rules.classify_task_ref` on the server, which
/// governs. This copy lets the box refuse junk without a round trip. A test,
/// `task_lookup_test.dart`, pins it to the same numbers.
library;

/// The shortest prefix the server will resolve.
const minTaskRefPrefixLen = 4;

/// How a typed reference classifies.
enum TaskRefKind {
  /// A complete task id.
  full,

  /// A hex prefix of at least [minTaskRefPrefixLen] characters.
  prefix,

  /// Text that is not a task reference.
  invalid
}

/// A classified reference; [value] is null exactly when [kind] is invalid.
class TaskRef {
  /// The classification.
  final TaskRefKind kind;

  /// The normalised id or prefix, or null when invalid.
  final String? value;

  /// Creates a classified reference.
  const TaskRef( this.kind, this.value );
}

final _canonicalUuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
final _hexOnly = RegExp( r'^[0-9a-f]+$' );
const _compactUuidLen = 32;

/// Classifies what the user typed; pure and never throws.
///
/// Requires:
///   - [ref] is the raw text from the box; null is allowed
///
/// Ensures:
///   - a canonical UUID, or 32 bare hex chars, is full and lowercased
///   - at least [minTaskRefPrefixLen] hex chars, hyphens tolerated, is a prefix with the
///     hyphens stripped
///   - anything else is invalid, with a null value
///   - junk never classifies as a prefix, because a lookup built from arbitrary text is a
///     search box, which is a different feature
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
///   - a classifiable ref gives `/api/tasks/<normalized>`, so two spellings of one id
///     produce one URL
///   - junk gives null, so the box can refuse it without spending a round trip on a 422
String? taskLookupPath( String? ref ) {
  final classified = classifyTaskRef( ref );
  if ( classified.kind == TaskRefKind.invalid ) return null;
  return '/api/tasks/${Uri.encodeComponent( classified.value! )}';
}

/// Shown when the typed text will not classify; worded as the web words it.
const taskRefRefusalMessage =
    'Enter at least $minTaskRefPrefixLen hex characters of a ticket id (0-9, a-f). '
    'Hyphens are fine — paste as much of the id as you have.';

/// Shown on a 401. The web says "refresh the page"; a phone has no page to refresh.
const taskLookupAuthRequiredMessage = 'Signed out — sign back in to look up tickets.';

/// Shown when the store did not answer.
///
/// The server's own text is not passed through on this arm, as on the web. A 5xx's
/// message is "HTTP 500" or a stack fragment, which the reader cannot act on.
const taskLookupUnreachableMessage = 'The store did not answer. Try again in a moment.';

/// A lookup the server answered with something other than a row.
class TaskLookupException implements Exception {
  /// The HTTP status, or 0 when there was no response at all.
  final int status;

  /// FastAPI's `detail`, when the server sent one.
  final String? detail;

  /// Creates the exception.
  const TaskLookupException( this.status, { this.detail } );

  @override
  String toString() => 'TaskLookupException($status, $detail)';
}

/// What the box says when a lookup failed.
///
/// Ensures:
///   - 404 names what was typed, so a typo is visible
///   - 422 passes the server's `detail` through, because for an ambiguous prefix it names
///     the candidate ids and is the most useful text on the screen
///   - 401 gives the sign-in sentence
///   - anything else gives the unreachable sentence
String describeLookupFailure( String typed, TaskLookupException error ) {
  switch ( error.status ) {
    case 404 : return 'No ticket matches "$typed".';
    case 422 : return error.detail ?? '"$typed" is not a usable ticket reference.';
    case 401 : return taskLookupAuthRequiredMessage;
    default  : return taskLookupUnreachableMessage;
  }
}
