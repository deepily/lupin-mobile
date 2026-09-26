import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../../fleet/data/task_row_model.dart';
import '../../fleet/presentation/task_row.dart';
import '../data/task_lookup.dart';

/// The top of the Task List: the count headline, the new-task stub and the lookup box
/// (walk-through items M1, M4 and M3 — Rick, emulator, 2026-09-22).
///
/// ⚠️ THE LOOKUP STATE LIVES HERE, NOT IN THE BLOC. The answer is one ticket that is
/// usually NOT on the board — held, parked or finished — so it must never be folded into
/// board state, where a held row would read as owed work.
class TaskListHeader extends StatefulWidget {
  /// The headline text from `taskListCountLabel`, or null before the first page lands.
  final String? countLabel;

  /// Performs the GET for a path built by `taskLookupPath`.
  final Future<TaskRowModel> Function( String path ) lookup;

  const TaskListHeader( { super.key, required this.countLabel, required this.lookup } );

  @override
  State<TaskListHeader> createState() => _TaskListHeaderState();
}

class _TaskListHeaderState extends State<TaskListHeader> {
  final _controller = TextEditingController();

  /// The sentence under the box: a refusal, "Looking up…", or a failure.
  String? _message;

  /// The ticket found, shown as a card.
  TaskRowModel? _found;

  /// Guards against an older lookup landing after a newer one or after a clear.
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
      // A row the model cannot parse. Say so rather than sit on "Looking up…" forever.
      if ( !mounted || gen != _generation ) return;
      setState( () => _message = taskLookupUnreachableMessage );
    }
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
              // M4: a STUB, on Rick's word — *"I understand the new task item creator is
              // a next phase implementation, I expected to see these things stubbed in."*
              // Disabled but visible, so the screen has its final shape.
              Tooltip(
                message : 'Creating tasks from the phone comes in a later phase',
                child   : OutlinedButton.icon(
                  key       : const Key( TestKeys.taskListNewTaskStub ),
                  onPressed : null,
                  icon      : const Icon( Icons.add, size: 18 ),
                  label     : const Text( 'New task' ),
                ),
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

  /// The found ticket, as a card rather than a scroll-to-row: the rows Rick looks up are
  /// usually not on the board, so there is nothing to scroll to.
  ///
  /// 🔴 THE STATUS IS PART OF THE ANSWER, NOT DECORATION. A held row without its status
  /// reads as an ordinary queued ticket, and "it is sitting in your holding area" is
  /// usually the whole reason he asked.
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
