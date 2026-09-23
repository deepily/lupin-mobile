import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../data/task_verbs.dart';
import '../data/task_write_repository.dart';

/// The ONE reason surface for per-row verbs. Task List and Holding Area both open this
/// and get the same sheet.
///
/// 🔴 THERE IS NO PANE PARAMETER, FOR THE SAME REASON `TaskRow` HAS NONE. "Build one
/// widget" is an instruction, not a mechanism: `VerbReasonSheet( verb: v, pane:
/// Pane.holdingArea )` satisfies every word of it and is one enum case away from two
/// divergent sheets. This constructor takes a verb and a row title and nothing that can
/// tell it which pane opened it, so drift requires changing the constructor — which is
/// visible in review.
///
/// 🔴 A SHEET, NOT A DIALOG, AND THAT IS §3a's PROPOSAL RATHER THAN A PREFERENCE.
/// The gap analysis asked where a phone user types a per-row reason and answered: *"a
/// bottom sheet opened from the row's verb, with the reason box and each verb's own
/// complaint text."* The batch box on the Holding Area is deliberately NOT a modal for a
/// reason that does not carry here — the operator must read the group WHILE typing — but
/// a per-row reason names ONE row, and the sheet carries that row's title at the top so
/// the thing being closed is on screen with the justification for closing it.
///
/// ⚠️ THE SHEET IS NOT THE CONFIRM. The terminal verbs still arm in the row before this
/// ever opens (§7.4), with the live-region announcement that makes arming mean something
/// under TalkBack. This sheet is where the operator supplies what the verb needs and
/// sees what will be recorded; it is not a second-guessing step bolted on in front of it.
class VerbReasonSheet extends StatefulWidget {
  /// The verb being filled in. Data, not a discriminator — both panes pass verb names
  /// from the same table.
  final VerbNeeds needs;

  /// The title of the row this verb will be applied to, so the operator can see WHAT
  /// they are about to park or close while they justify it.
  final String rowTitle;

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

  /// The complaints currently shown. Null until the operator presses Submit — a sheet
  /// that opened already complaining would be scolding someone who has not done anything
  /// yet.
  String? _reasonError;
  String? _dateError;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build( BuildContext context ) {
    // ⚠️ `viewInsets`, OR THE KEYBOARD EATS THE SUBMIT BUTTON. A bottom sheet with a text
    // field sits exactly where the soft keyboard opens, and at 360×800 the control the
    // operator must reach next is the first thing to go under it.
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

  /// The verb and the row it will be applied to, in one sentence.
  ///
  /// ⚠️ THE ROW TITLE IS HERE BECAUSE THE SHEET COVERS THE ROW. A modal that hides the
  /// thing it is about asks the operator to justify a decision from memory, and on a
  /// grouped board every title shares a prefix — "the third one down" is not an
  /// identification.
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

  /// The reason box, wearing THIS verb's prompt and THIS verb's complaint.
  ///
  /// 🔴 ONE BOX, SEVEN VERBS, AND NOT ONE SENTENCE BETWEEN THEM. *"'A reason is required'
  /// is true of four of them and teaches none of them"* (`taskVerbs.ts:160-165`). The
  /// hint comes from the verb's own table entry and the complaint from
  /// [verbReasonComplaint], so adding verb number eight cannot accidentally inherit
  /// park's wording.
  ///
  /// ⚠️ `errorText` RATHER THAN A KEYED `Text` BELOW THE FIELD — the same call the
  /// Holding Area's batch box made. It is what Flutter wires into the field's OWN
  /// semantics, so TalkBack reads the complaint as part of the box instead of as a stray
  /// sentence the user has to go find.
  Widget _reasonBox( BuildContext context ) {
    return TextField(
      key        : const Key( TestKeys.reasonSheetReason ),
      controller : _reason,
      autofocus  : true,
      minLines   : 2,
      maxLines   : 4,
      onChanged  : ( _ ) {
        // Clear the complaint the moment the operator answers it. A refusal that stays
        // on screen while the box now holds a reason is a refusal that is lying.
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

  /// What the sheet says for the verbs that ask for no reason.
  ///
  /// 🔴 THIS IS THE `fixed` BRANCH, AND IT IS THE HALF OF THIS SHEET THAT IS NOT A TEXT
  /// BOX. Fixed sends `receipt_refs.operator_attestation` and no reason at all; the
  /// server refuses a `->done` with an empty receipt and then REPLACES the string with
  /// the validated login identity. So there is nothing for the operator to type — but
  /// there IS something for them to read, because this press closes the row for good.
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

  /// The chase / triage date, for the two verbs that are BOUNDED.
  ///
  /// 🔴 A PARK WITHOUT A DATE IS NOT A PARK WITH NO DATE — IT IS A PARK THAT CLEARS ONE.
  /// `TaskVerb.park` always puts `next_chase_ts` in the body, and §4.3 note 2 is explicit
  /// that *"'send nothing' and 'send null' are different requests and only one of them
  /// clears"*. A sheet with no date field would therefore send the CLEARING value on
  /// every park, silently, which is why this is required rather than optional.
  ///
  /// ⚠️ THE LABEL NAMES THE QUESTION, NOT THE FIELD. Rick on the web control: *"I really
  /// have no idea what the date chooser is for."* Park asks "Chase me again on"; demote
  /// asks "Triage this by".
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
            // A live region: the complaint appears in response to a press, and a TalkBack
            // user whose focus is still on Submit is told nothing otherwise. The reason
            // box gets this for free through `errorText`; a button does not.
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

  /// `yyyy-mm-dd`, which is unambiguous in every locale this app can land in.
  static String _dayLabel( DateTime d ) =>
      '${d.year.toString().padLeft( 4, '0' )}-'
      '${d.month.toString().padLeft( 2, '0' )}-'
      '${d.day.toString().padLeft( 2, '0' )}';

  Future<void> _pickDate( BuildContext context ) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context     : context,
      initialDate : _chaseTs ?? now.add( const Duration( days: 7 ) ),
      // A chase date in the past is a chase that has already lapsed, which is the one
      // thing a bounded park must not be.
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
          // The verb, not "OK". The button still reads correctly when it is the only
          // thing focus lands on.
          child : Text( widget.needs.label ),
        ),
      ],
    );
  }

  /// Refuse client-side, then build the payload.
  ///
  /// 🔴 THE CLIENT-SIDE REFUSAL EXISTS SO THE SERVER DOES NOT HAVE TO SAY IT. The web's
  /// reasoning, carried: the alternative is a 422 the operator must read to learn a
  /// single fact they could have been told before the round trip — and on a phone that
  /// round trip may not come back at all.
  ///
  /// Ensures:
  ///   - a blank required reason pops nothing and shows THIS verb's complaint
  ///   - a missing required date pops nothing and shows THIS verb's date complaint
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

/// Open the shared sheet for [needs] and return the verb the operator built, or null if
/// they backed out.
///
/// ⚠️ `isScrollControlled: true` OR THE KEYBOARD COVERS THE SHEET. The default bottom
/// sheet is capped at half the screen and does not move for `viewInsets`, so at 360×800
/// the reason box and the Submit button end up under the soft keyboard together.
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
