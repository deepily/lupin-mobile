import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../data/task_verbs.dart';
import '../data/task_write_repository.dart';
import '../../../shared/widgets/dictation_text_field.dart';

/// The one reason sheet for per-row verbs, shared by Task List and Holding Area.
///
/// It has no pane parameter, for the reason `TaskRow` has none. The constructor takes a
/// verb and a row title and nothing that says which pane opened it. Drift then needs a
/// constructor change, which shows up in review. It is a bottom sheet, not a dialog,
/// opened from the row's verb with the reason box and the verb's own complaint text. It
/// carries the row title, so the row being closed is on screen with the justification.
/// The Holding Area batch box is not a modal, because the operator reads the group while
/// typing.
///
/// The sheet is not the confirm. Terminal verbs arm in the row, with a live-region
/// announcement for TalkBack, before this opens. The sheet is where the operator supplies
/// what the verb needs and sees what will be recorded.
class VerbReasonSheet extends StatefulWidget {
  /// The verb being filled in; data from the shared verb table, not a pane discriminator.
  final VerbNeeds needs;

  /// The title of the row this verb applies to, shown above the reason box.
  ///
  /// It tells the operator which row they are about to park or close.
  final String rowTitle;

  /// Creates the sheet for one verb on one row.
  const VerbReasonSheet( {
    super.key,
    required this.needs,
    required this.rowTitle,
  } );

  @override
  State<VerbReasonSheet> createState() => _VerbReasonSheetState();
}

class _VerbReasonSheetState extends State<VerbReasonSheet> {
  final TextEditingController _reason = TextEditingController();

  DateTime? _chaseTs;

  // The complaints currently shown; null until the operator presses Submit, so the sheet
  // does not open already complaining.
  String? _reasonError;
  String? _dateError;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build( BuildContext context ) {
    // The `viewInsets` padding keeps the soft keyboard off the Submit button. A bottom
    // sheet with a text field sits where the keyboard opens, and at 360x800 the next
    // control the operator must reach is the first to go under it.
    return Padding(
      key     : const Key( TestKeys.reasonSheet ),
      padding : EdgeInsets.only(
        left   : 16,
        right  : 16,
        top    : 16,
        bottom : MediaQuery.of( context ).viewInsets.bottom + 16,
      ),
      child : Column(
        mainAxisSize       : MainAxisSize.min,
        crossAxisAlignment : CrossAxisAlignment.stretch,
        children : [
          _title( context ),
          const SizedBox( height: 12 ),
          if ( widget.needs.reason ) _reasonBox( context ) else _noReasonNotice( context ),
          if ( widget.needs.date ) ...[
            const SizedBox( height: 12 ),
            _dateField( context ),
          ],
          const SizedBox( height: 16 ),
          _actions( context ),
        ],
      ),
    );
  }

  // The verb and the row it applies to. The sheet covers the row, so the title is shown
  // here; otherwise the operator would justify a decision from memory, and on a grouped
  // board every title shares a prefix.
  Widget _title( BuildContext context ) {
    return Column(
      crossAxisAlignment : CrossAxisAlignment.start,
      children : [
        Text(
          widget.needs.label,
          style : Theme.of( context ).textTheme.titleMedium,
        ),
        const SizedBox( height: 4 ),
        Text(
          widget.rowTitle,
          style    : Theme.of( context ).textTheme.bodySmall,
          maxLines : 2,
          overflow : TextOverflow.ellipsis,
        ),
      ],
    );
  }

  // The reason box with this verb's prompt and complaint. The hint comes from the verb's
  // table entry and the complaint from [verbReasonComplaint], so a new verb cannot
  // inherit park's wording. The complaint is `errorText`, not a separate `Text` below the
  // field, so Flutter wires it into the field's own semantics and TalkBack reads it as
  // part of the box.
  Widget _reasonBox( BuildContext context ) {
    return DictationTextField(
      fieldKey   : const Key( TestKeys.reasonSheetReason ),
      controller : _reason,
      autofocus  : true,
      minLines   : 2,
      maxLines   : 4,
      onChanged  : ( _ ) {
        // Clear the complaint as soon as the operator answers it; a stale refusal would
        // be wrong.
        if ( _reasonError != null ) setState( () => _reasonError = null );
      },
      decoration : InputDecoration(
        labelText : 'Reason',
        hintText  : widget.needs.placeholder,
        errorText : _reasonError,
        border    : const OutlineInputBorder(),
        isDense   : true,
      ),
    );
  }

  // What the sheet says for verbs that ask for no reason, chiefly `fixed`. It sends
  // `receipt_refs.operator_attestation` and no reason, so there is nothing to type, but
  // the operator still reads what will be recorded because the press closes the row.
  Widget _noReasonNotice( BuildContext context ) {
    final terminal = widget.needs.terminal;
    return Text(
      key   : const Key( TestKeys.reasonSheetNoReason ),
      terminal
          ? '${widget.needs.placeholder}. This closes the row for good, and is recorded '
            'against your login.'
          : '${widget.needs.placeholder}.',
      style : Theme.of( context ).textTheme.bodyMedium,
    );
  }

  // The chase or triage date, for the two bounded verbs. It is required, not optional:
  // `TaskVerb.park` always puts `next_chase_ts` in the body, and a null there clears the
  // date, so a sheet without a date field would clear it on every park. The label names
  // the question: park asks "Chase me again on" and demote asks "Triage this by".
  Widget _dateField( BuildContext context ) {
    final chosen = _chaseTs;
    return Column(
      crossAxisAlignment : CrossAxisAlignment.start,
      children : [
        OutlinedButton.icon(
          key       : const Key( TestKeys.reasonSheetDate ),
          onPressed : () => _pickDate( context ),
          icon      : const Icon( Icons.event ),
          style     : OutlinedButton.styleFrom(
            minimumSize : const Size( 0, kMinInteractiveDimension ),
          ),
          label : Text(
            chosen == null
                ? widget.needs.dateLabel
                : '${widget.needs.dateLabel}: ${_dayLabel( chosen )}',
          ),
        ),
        if ( _dateError != null )
          Padding(
            padding : const EdgeInsets.only( top: 4 ),
            // A live region: the complaint appears after a press, and a TalkBack user whose
            // focus is still on Submit would otherwise hear nothing. The reason box gets
            // this through `errorText`; a button does not.
            child   : Semantics(
              liveRegion : true,
              child      : Text(
                _dateError!,
                key   : const Key( TestKeys.reasonSheetDateError ),
                style : TextStyle( color: Theme.of( context ).colorScheme.error ),
              ),
            ),
          ),
      ],
    );
  }

  // `yyyy-mm-dd`, which is unambiguous in every locale.
  static String _dayLabel( DateTime d ) =>
      '${d.year.toString().padLeft( 4, '0' )}-'
      '${d.month.toString().padLeft( 2, '0' )}-'
      '${d.day.toString().padLeft( 2, '0' )}';

  Future<void> _pickDate( BuildContext context ) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context     : context,
      initialDate : _chaseTs ?? now.add( const Duration( days: 7 ) ),
      // A chase date in the past has already lapsed, which a bounded park must not be.
      firstDate   : now,
      lastDate    : now.add( const Duration( days: 365 * 2 ) ),
    );
    if ( picked == null ) return;
    setState( () {
      _chaseTs   = picked;
      _dateError = null;
    } );
  }

  Widget _actions( BuildContext context ) {
    return Row(
      mainAxisAlignment : MainAxisAlignment.end,
      children : [
        TextButton(
          key       : const Key( TestKeys.reasonSheetCancel ),
          onPressed : () => Navigator.of( context ).pop(),
          child     : const Text( 'Cancel' ),
        ),
        const SizedBox( width: 8 ),
        FilledButton(
          key       : const Key( TestKeys.reasonSheetSubmit ),
          onPressed : _submit,
          style     : FilledButton.styleFrom(
            minimumSize : const Size( 0, kMinInteractiveDimension ),
          ),
          // The verb, not "OK", so the button reads correctly when it is the only thing
          // focus lands on.
          child : Text( widget.needs.label ),
        ),
      ],
    );
  }

  /// Refuses a blank required field on the client, then pops the built verb.
  ///
  /// The client-side refusal saves a 422 round trip to learn one fact. On a phone that
  /// round trip may not come back at all.
  ///
  /// Ensures:
  ///   - a blank required reason pops nothing and shows this verb's complaint
  ///   - a missing required date pops nothing and shows this verb's date complaint
  ///   - otherwise pops the built [TaskVerb], reason trimmed
  void _submit() {
    final needs = widget.needs;
    final text  = _reason.text.trim();

    final reasonMissing = needs.reason && text.isEmpty;
    final dateMissing   = needs.date && _chaseTs == null;

    if ( reasonMissing || dateMissing ) {
      setState( () {
        _reasonError = reasonMissing ? verbReasonComplaint( needs.name ) : null;
        _dateError   = dateMissing ? verbDateComplaint( needs.name ) : null;
      } );
      return;
    }

    Navigator.of( context ).pop(
      buildTaskVerb( needs.name, reason: text, chaseTs: _chaseTs ),
    );
  }
}

/// Opens the shared sheet for [needs]; returns the verb the operator built, or null.
///
/// It sets `isScrollControlled: true`. The default bottom sheet is capped at half the
/// screen and ignores `viewInsets`. At 360x800 the reason box and Submit would end up
/// under the soft keyboard.
///
/// Requires:
///   - needs is a verb whose [VerbNeeds.needsSheet] is true
///
/// Ensures:
///   - returns null when the operator cancels or dismisses the sheet
///   - returns a [TaskVerb] whose required fields are all non-blank
Future<TaskVerb?> showVerbReasonSheet(
  BuildContext context, {
  required VerbNeeds needs,
  required String rowTitle,
} ) {
  return showModalBottomSheet<TaskVerb>(
    context            : context,
    isScrollControlled : true,
    builder            : ( _ ) => VerbReasonSheet( needs: needs, rowTitle: rowTitle ),
  );
}
