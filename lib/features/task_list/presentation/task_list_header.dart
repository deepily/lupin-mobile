import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../../fleet/data/task_row_model.dart';
import '../../fleet/presentation/task_row.dart';
import '../data/new_ticket.dart';
import '../data/task_lookup.dart';
import 'new_ticket_sheet.dart';

/// The top of the Task List: the count headline, the New task button and the lookup box.
///
/// The lookup state lives here, not in the bloc. The answer is one ticket that is usually
/// not on the board, being held, parked or finished. It must never be folded into board
/// state, where a held row would read as owed work.
class TaskListHeader extends StatefulWidget {
  /// The headline text from `taskListCountLabel`, or null before the first page lands.
  final String? countLabel;

  /// Performs the GET for a path built by `taskLookupPath`.
  final Future<TaskRowModel> Function( String path ) lookup;

  /// Files one ticket from the New Ticket card.
  final Future<NewTicketOutcome> Function( Map<String, String> payload ) createTicket;

  /// The names the card offers under "Assigned to", read when the card opens.
  ///
  /// Reading then keeps the roster current.
  final List<String> Function() assignees;

  /// Creates the header.
  const TaskListHeader( {
    super.key,
    required this.countLabel,
    required this.lookup,
    required this.createTicket,
    required this.assignees,
  } );

  @override
  State<TaskListHeader> createState() => _TaskListHeaderState();
}

class _TaskListHeaderState extends State<TaskListHeader> {
  final _controller = TextEditingController();

  // The sentence under the box: a refusal, "Looking up...", or a failure.
  String? _message;

  // The ticket found, shown as a card.
  TaskRowModel? _found;

  // Guards against an older lookup landing after a newer one or after a clear.
  int _generation = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final typed = _controller.text.trim();
    final path  = taskLookupPath( typed );
    final gen   = ++_generation;

    if ( path == null ) {
      setState( () { _message = taskRefRefusalMessage; _found = null; } );
      return;
    }

    setState( () { _message = 'Looking up…'; _found = null; } );
    try {
      final row = await widget.lookup( path );
      if ( !mounted || gen != _generation ) return;
      setState( () { _message = null; _found = row; } );
    } on TaskLookupException catch ( e ) {
      if ( !mounted || gen != _generation ) return;
      setState( () => _message = describeLookupFailure( typed, e ) );
    } catch ( _ ) {
      // A row the model cannot parse: say so instead of sitting on "Looking up..." forever.
      if ( !mounted || gen != _generation ) return;
      setState( () => _message = taskLookupUnreachableMessage );
    }
  }

  Future<void> _openNewTicket() async {
    final outcome = await showNewTicketSheet(
      context,
      createTicket : widget.createTicket,
      assignees    : widget.assignees(),
    );
    if ( outcome == null || !mounted ) return;
    // The card closed itself on `created`; its sentence moves here so it is not lost.
    ScaffoldMessenger.maybeOf( context )?.showSnackBar( SnackBar( content: Text( outcome.text ) ) );
  }

  void _clear() {
    _generation++;
    _controller.clear();
    setState( () { _message = null; _found = null; } );
  }

  @override
  Widget build( BuildContext context ) {
    final theme    = Theme.of( context );
    final hasState = _message != null || _found != null || _controller.text.isNotEmpty;

    return Padding(
      padding : const EdgeInsets.fromLTRB( 16, 8, 16, 4 ),
      child   : Column(
        crossAxisAlignment : CrossAxisAlignment.stretch,
        mainAxisSize       : MainAxisSize.min,
        children           : [
          Row(
            children : [
              Expanded(
                child : Text(
                  widget.countLabel ?? '',
                  key   : const Key( TestKeys.taskListCountHeadline ),
                  style : theme.textTheme.titleSmall,
                ),
              ),
              // The New Ticket card, the web's field for field.
              OutlinedButton.icon(
                key       : const Key( TestKeys.taskListNewTask ),
                onPressed : _openNewTicket,
                icon      : const Icon( Icons.add, size: 18 ),
                label     : const Text( 'New task' ),
              ),
            ],
          ),
          const SizedBox( height: 8 ),
          TextField(
            key             : const Key( TestKeys.taskLookupInput ),
            controller      : _controller,
            textInputAction : TextInputAction.search,
            autocorrect     : false,
            onSubmitted     : ( _ ) => _submit(),
            onChanged       : ( _ ) => setState( () {} ),
            decoration      : InputDecoration(
              isDense    : true,
              hintText   : 'Find ticket by id…',
              border     : const OutlineInputBorder(),
              prefixIcon : IconButton(
                key       : const Key( TestKeys.taskLookupGo ),
                tooltip   : 'Look up a ticket by its id',
                icon      : const Icon( Icons.search ),
                onPressed : _submit,
              ),
              suffixIcon : hasState
                  ? IconButton(
                      key       : const Key( TestKeys.taskLookupClear ),
                      tooltip   : 'Clear the lookup',
                      icon      : const Icon( Icons.close ),
                      onPressed : _clear,
                    )
                  : null,
            ),
          ),
          if ( _message != null )
            Semantics(
              liveRegion : true,
              child      : Padding(
                padding : const EdgeInsets.only( top: 6 ),
                child   : Text( _message!, key: const Key( TestKeys.taskLookupMessage ) ),
              ),
            ),
          if ( _found != null ) _resultCard( context, _found! ),
        ],
      ),
    );
  }

  // The found ticket, as a card rather than a scroll-to-row, because looked-up rows are
  // usually not on the board and there is nothing to scroll to. The status is part of the
  // answer: a held row without its status reads as an ordinary queued ticket, and "it is
  // sitting in the holding area" is usually why the operator asked.
  Widget _resultCard( BuildContext context, TaskRowModel row ) {
    return Card(
      key    : const Key( TestKeys.taskLookupResultCard ),
      margin : const EdgeInsets.only( top: 8 ),
      child  : Padding(
        padding : const EdgeInsets.all( 8 ),
        child   : Column(
          crossAxisAlignment : CrossAxisAlignment.start,
          mainAxisSize       : MainAxisSize.min,
          children           : [
            Semantics(
              liveRegion : true,
              child      : Text(
                lookupStatusSentence( row.status ),
                key   : const Key( TestKeys.taskLookupResultStatus ),
                style : Theme.of( context ).textTheme.labelLarge,
              ),
            ),
            const SizedBox( height: 4 ),
            // Read-only: no verbs. Acting on a row belongs to the pane that owns it.
            // taskrow-omit: verbs read-only lookup, acting belongs to the owning pane
            // taskrow-omit: onVerb no verbs are offered, so nothing can fire
            // taskrow-omit: onFieldChanged read-only lookup, no field edits
            // taskrow-omit: ownerOptions no field edits, so no reassign targets
            // taskrow-omit: unsentLabel nothing is written from here, so nothing is unsent
            TaskRow( model: row ),
          ],
        ),
      ),
    );
  }
}

/// The status line on a lookup result, naming where the row actually is.
///
/// Ensures:
///   - `not_approved` says it is in the holding area
///   - `parked` says it is parked
///   - terminal statuses say the ticket is finished
///   - anything else is `Status: <status>`
String lookupStatusSentence( String status ) {
  switch ( status ) {
    case 'not_approved' : return 'Status: not_approved — in the holding area, awaiting approval';
    case 'parked'       : return 'Status: parked — approved, not now';
    case 'done'         :
    case 'dropped'      :
    case 'wont_fix'     : return 'Status: $status — finished';
    case ''             : return 'Status: unknown';
    default             : return 'Status: $status';
  }
}
