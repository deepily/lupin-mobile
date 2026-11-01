import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../core/testing/test_keys.dart';
import '../../fleet/data/task_row_model.dart';
import '../../fleet/data/task_write_repository.dart';
import '../../task_list/data/task_list_repository.dart';
import '../../task_list/data/task_lookup.dart';
import '../data/task_link.dart';

/// What an approve link shows right now.
enum TaskLinkPhase {
  /// The live link, ready to tap.
  live,

  /// The request is out; a second tap sends nothing.
  sending,

  /// Disabled text "approved ✅".
  approved,

  /// The row was turned down; its status is shown in plain text.
  closed,

  /// The server refused or held the approval; its words are shown.
  refused,
}

/// One row's approve-link state, shared by every link in the card that names the row.
class TaskLinkState {
  /// Which of the five looks the link has.
  final TaskLinkPhase phase;

  /// The text shown for [TaskLinkPhase.closed] and [TaskLinkPhase.refused].
  final String? text;

  /// Creates a state.
  const TaskLinkState( this.phase, [ this.text ] );
}

/// What an approved link reads.
const String approvedText = "approved ✅";

/// Statuses that mean the row was turned down; shown as plain text, never as approved.
const Set<String> _closedStatuses = { "dropped", "wont_fix" };

/// One text block for a row: title, priority, owner, status and body.
///
/// Ensures:
///   - a missing field reads as a dash, "unowned" or "(no body)", never "null"
String taskOverlayText( TaskRowModel row ) {
  final facts = "Priority: ${row.priority ?? "—"} · Owner: ${row.ownerPersona ?? "unowned"}"
      " · Status: ${row.status.isEmpty ? "—" : row.status}";
  final title = row.title.isEmpty ? "(no title)" : row.title;
  return "$title\n$facts\n\n${row.detail ?? "(no body)"}";
}

/// The approve-link state for one drawn card, and the only sender of its requests.
///
/// One session lives as long as the markdown it serves. It reads each row once however
/// many links name it, and it sends at most one approve per row at a time.
class TaskLinkSession extends ChangeNotifier {
  /// The shared write surface; this class adds no second HTTP path.
  final TaskWriteRepository repository;

  /// The shared single-row read, `TaskListRepository.lookup`.
  final TaskListRepository reader;

  final Map<String, TaskLinkState> _states = <String, TaskLinkState>{};
  final Set<String>                _read   = <String>{};
  bool _disposed = false;

  /// Creates a session over [repository].
  TaskLinkSession( this.repository, this.reader );

  /// The current state of [id]; live until something says otherwise.
  TaskLinkState stateFor( String id ) =>
      _states[ id ] ?? const TaskLinkState( TaskLinkPhase.live );

  void _set( String id, TaskLinkState state ) {
    if ( _disposed ) return;
    _states[ id ] = state;
    notifyListeners();
  }

  /// Reads [id] in full through the shared lookup door.
  ///
  /// Raises:
  ///   - TaskLookupException when the read fails
  Future<TaskRowModel> readRow( String id ) => reader.lookup( taskLookupPath( id )! );

  /// Reads [id] once for the drawn card and settles the link by the row's status.
  ///
  /// Ensures:
  ///   - a second call for the same id does nothing, so a row named twice is read once
  ///   - `not_approved`, an unknown status or a failed read leaves the live link
  ///   - any other status shows approved, except dropped or wont_fix, shown as that status
  ///   - a link already tapped is not overwritten
  Future<void> ensureRead( String id ) async {
    if ( !_read.add( id ) ) return;
    final TaskRowModel row;
    try {
      row = await readRow( id );
    } on TaskLookupException {
      return;
    }
    if ( stateFor( id ).phase != TaskLinkPhase.live ) return;
    if ( row.status.isEmpty || row.status == "not_approved" ) return;
    _set( id, _closedStatuses.contains( row.status )
        ? TaskLinkState( TaskLinkPhase.closed, row.status )
        : const TaskLinkState( TaskLinkPhase.approved ) );
  }

  /// Sends the approve move for [id].
  ///
  /// Ensures:
  ///   - nothing is sent while a request for the row is out or once it has settled
  ///   - success shows approved; a refusal shows the server's reason word for word
  Future<void> approve( String id ) async {
    if ( stateFor( id ).phase != TaskLinkPhase.live ) return;
    _set( id, const TaskLinkState( TaskLinkPhase.sending ) );
    try {
      await repository.transition( id: id, verb: TaskVerb.approve() );
      _set( id, const TaskLinkState( TaskLinkPhase.approved ) );
    } on TaskAwaitingApprovalException {
      _set( id, const TaskLinkState( TaskLinkPhase.refused, TaskWriteRepository.awaitingHumanApproval ) );
    } on TaskWriteException catch ( e ) {
      _set( id, TaskLinkState( TaskLinkPhase.refused, e.serverMessage ?? e.message ) );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Matches a markdown inline link, the same shape `doc_link.dart` parses.
final RegExp _markdownLink = RegExp( r'\[([^\]]*)\]\(([^)\s]+)\)' );

/// Escapes markdown punctuation so server text shows exactly as sent.
String escapeMarkdown( String text ) =>
    text.replaceAllMapped( RegExp( r'[\\`*_{}\[\]()#+\-.!|<>~$&]' ), ( m ) => '\\${m[ 0 ]}' );

/// Draws markdown whose approve and view links act in place.
///
/// A task link is recognised by its address, never by its label. An approve link is
/// redrawn from the session's state, as live link, plain label, "approved ✅", status or
/// refusal. A view link opens the row's text in a dialog. Every other link is left to
/// [onTapLink]. With no [repository] the task links stay ordinary links.
class TaskLinkMarkdown extends StatefulWidget {
  /// The markdown source.
  final String data;

  /// The write surface for the task links; null leaves them inert.
  final TaskWriteRepository? repository;

  /// The row reader for the task links; null leaves them inert.
  final TaskListRepository? reader;

  /// Handles a tap on any other link.
  final MarkdownTapLinkCallback? onTapLink;

  /// Creates the markdown view.
  const TaskLinkMarkdown( { super.key, required this.data, this.repository, this.reader, this.onTapLink } );

  @override
  State<TaskLinkMarkdown> createState() => _TaskLinkMarkdownState();
}

class _TaskLinkMarkdownState extends State<TaskLinkMarkdown> {
  TaskLinkSession? _session;

  @override
  void initState() {
    super.initState();
    _rebuildSession();
  }

  @override
  void didUpdateWidget( TaskLinkMarkdown old ) {
    super.didUpdateWidget( old );
    if ( old.data != widget.data || old.repository != widget.repository || old.reader != widget.reader ) _rebuildSession();
  }

  // One session per drawn card: it reads each approve row once, however often it is named.
  void _rebuildSession() {
    _session?.dispose();
    final repo   = widget.repository;
    final reader = widget.reader;
    final next   = repo == null || reader == null ? null : TaskLinkSession( repo, reader );
    _session = next;
    if ( next == null ) return;
    for ( final m in _markdownLink.allMatches( widget.data ) ) {
      final link = classifyTaskHref( m.group( 2 ) );
      if ( link != null && link.kind == TaskLinkKind.approve ) next.ensureRead( link.id );
    }
  }

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  String _display( TaskLinkSession session ) => widget.data.replaceAllMapped( _markdownLink, ( m ) {
        final link = classifyTaskHref( m.group( 2 ) );
        if ( link == null || link.kind != TaskLinkKind.approve ) return m[ 0 ]!;
        final state = session.stateFor( link.id );
        switch ( state.phase ) {
          case TaskLinkPhase.live     : return m[ 0 ]!;
          case TaskLinkPhase.sending  : return escapeMarkdown( m.group( 1 ) ?? "" );
          case TaskLinkPhase.approved : return approvedText;
          case TaskLinkPhase.closed   :
          case TaskLinkPhase.refused  : return escapeMarkdown( state.text ?? "" );
        }
      } );

  void _onTap( String text, String? href, String title ) {
    final link = classifyTaskHref( href );
    final session = _session;
    if ( link == null || session == null ) {
      widget.onTapLink?.call( text, href, title );
      return;
    }
    if ( link.kind == TaskLinkKind.approve ) {
      session.approve( link.id );
      return;
    }
    showDialog<void>(
      context : context,
      builder : ( _ ) => _TaskBodyDialog( session: session, id: link.id ),
    );
  }

  @override
  Widget build( BuildContext context ) {
    final session = _session;
    if ( session == null ) {
      return Markdown(
        key        : const Key( TestKeys.docViewerMarkdown ),
        data       : widget.data,
        selectable : true,
        padding    : const EdgeInsets.all( 16 ),
        onTapLink  : widget.onTapLink,
      );
    }
    return ListenableBuilder(
      listenable: session,
      builder: ( context, _ ) => Markdown(
        key        : const Key( TestKeys.docViewerMarkdown ),
        data       : _display( session ),
        selectable : true,
        padding    : const EdgeInsets.all( 16 ),
        onTapLink  : _onTap,
      ),
    );
  }
}

// Reads the row on open and shows it as selectable plain text, never as markdown or HTML.
class _TaskBodyDialog extends StatefulWidget {
  final TaskLinkSession session;
  final String          id;

  const _TaskBodyDialog( { required this.session, required this.id } );

  @override
  State<_TaskBodyDialog> createState() => _TaskBodyDialogState();
}

class _TaskBodyDialogState extends State<_TaskBodyDialog> {
  late final Future<String> _text = widget.session
      .readRow( widget.id )
      .then( taskOverlayText )
      .catchError( ( Object _ ) => "Could not read this ticket." );

  @override
  Widget build( BuildContext context ) {
    return AlertDialog(
      key     : const Key( TestKeys.taskViewDialog ),
      title   : Text( widget.id.substring( 0, 8 ) ),
      content : SingleChildScrollView(
        child: FutureBuilder<String>(
          future  : _text,
          builder : ( context, snap ) => snap.hasData
              ? SelectableText( snap.data! )
              : const Center( child: CircularProgressIndicator() ),
        ),
      ),
      actions: [
        TextButton( onPressed: () => Navigator.of( context ).pop(), child: const Text( "Close" ) ),
      ],
    );
  }
}
