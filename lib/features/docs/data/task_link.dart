/// Recognises the task links a session writes into a card abstract.
///
/// The line is `- <title> [approve ☐](/app/tasks/approve?row=<uuid>) [📄](/app/tasks/view?row=<uuid>)`.
/// A link is recognised by its address, never by its label. It imports neither Flutter nor IO.

library;

/// What a task link does when tapped.
enum TaskLinkKind {
  /// Moves a held row to `queued`.
  approve,

  /// Shows the row's title, priority, owner and body.
  view,
}

/// One recognised task link.
class TaskLink {
  /// What a tap does.
  final TaskLinkKind kind;

  /// The full row id, as written in the href.
  final String id;

  /// Creates a task link.
  const TaskLink( { required this.kind, required this.id } );
}

// A full lowercase hyphenated row id, the only thing the app ever sends to the server.
final RegExp _rowIdPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// The task link [href] names, or null when it is any other link.
///
/// Requires:
///   - [href] may be null or malformed
///
/// Ensures:
///   - only the paths `/app/tasks/approve` and `/app/tasks/view` match
///   - a missing, short or non-uuid `row` is null, so nothing is sent for it
///   - never throws
TaskLink? classifyTaskHref( String? href ) {
  if ( href == null || !href.startsWith( "/app/tasks/" ) ) return null;
  final Uri uri;
  try {
    uri = Uri.parse( href );
  } catch ( _ ) {
    return null;
  }
  final TaskLinkKind kind;
  switch ( uri.path ) {
    case "/app/tasks/approve" : kind = TaskLinkKind.approve;
    case "/app/tasks/view"    : kind = TaskLinkKind.view;
    default                   : return null;
  }
  final id = uri.queryParameters[ "row" ];
  if ( id == null || !_rowIdPattern.hasMatch( id ) ) return null;
  return TaskLink( kind: kind, id: id );
}
