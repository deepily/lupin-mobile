import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../data/task_row_model.dart';
import '../data/task_row_schema.dart';
import '../data/task_verbs.dart';
import '../data/task_write_repository.dart';
import 'task_field_controls.dart';
import 'verb_reason_sheet.dart';

/// The ONE row widget. Task List and Holding Area both render this and produce
/// cell-for-cell identical output.
///
/// 🔴 THERE IS NO PANE PARAMETER, AND ITS ABSENCE IS THE WHOLE MECHANISM.
/// "Build one widget" is an instruction, not a mechanism — this satisfies every word of
/// it and is what a developer under deadline actually writes:
///
/// ```dart
/// TaskRow( model: row, pane: Pane.holdingArea )   // one widget, three behaviours
/// ```
///
/// One type, one constant, divergent layouts via `if (pane == …)` inside `build`. The
/// web comment protects CELL-FOR-CELL IDENTITY (`holdingAreaTable.ts:20-22`), and a
/// shared type delivers no part of that.
///
/// ⇒ The constructor takes a row model and nothing that can tell it which pane it is
/// in. Anything one pane needs that its sibling does not — the Holding Area's batch
/// selection — lives in the GROUP HEADER or a WRAPPER, never in a branch inside the row.
/// Drift then requires changing this constructor, which is visible in review; today it
/// would take adding an enum case, which is not.
///
/// ⚠️ FINISHED TASKS MUST NOT RENDER THIS. Its rows come from `task_events` and carry no
/// `priority`, `blocked`, `accountable` or `actions`. A guard test asserts its absence,
/// because §7's title — "The shared row" — reads to a later hand as a mandate to unify.
class TaskRow extends StatefulWidget {
  final TaskRowModel model;

  /// The verbs this row offers. Supplied by the pane, but as DATA — a list of verbs is
  /// not a pane discriminator: both panes may pass the same list, and neither can make
  /// the row lay itself out differently by choosing one.
  ///
  /// 🔴 THESE ARE OBLIGATIONS, NOT PAYLOADS, AND THE CHANGE IS NOT COSMETIC. This was
  /// `List<TaskVerb>` — a list of BUILT payloads — which works only for the two verbs
  /// that need nothing. Four of the seven require a reason the operator has not typed
  /// yet, so a pane building them eagerly would have to pass `TaskVerb.wontFix( reason:
  /// '' )`: a button whose every press is a guaranteed 422. The Holding Area named that
  /// exact trap and declined to ship the verb rather than fall into it.
  ///
  /// ⇒ The pane says WHICH verbs; the row collects what each one needs through the
  /// shared sheet and hands the pane a payload that is already complete.
  final List<VerbNeeds> verbs;

  /// Fired when the operator confirms a verb AND has supplied everything it requires.
  /// The row owns arming and the sheet; the pane owns the write and the optimistic
  /// rollback.
  final void Function( TaskVerb verb )? onVerb;

  /// Fired when the operator commits a FIELD change — priority or owner, never status.
  ///
  /// ⚠️ NULL MEANS "THIS PANE DOES NOT OFFER FIELD EDITS", AND IT IS NOT A PANE
  /// DISCRIMINATOR. It is the same shape [onVerb] already had: a callback the pane
  /// supplies or does not, exactly as it supplies a verb list or an empty one. Both
  /// panes may pass one, and neither can make the row lay itself out differently by
  /// choosing — the controls appear because there is somewhere for their output to go,
  /// which is a property of the DATA and not of which pane is asking.
  final void Function( { String? priority, String? ownerPersona } )? onFieldChanged;

  /// The personas this row may be reassigned to. Data, from the live fleet.
  final List<String> ownerOptions;

  /// What the operator did to this row that has NOT reached the server, if anything.
  ///
  /// 🔴 VISIBLE STATE, NOT ONLY A NOTICE. Gap G6's acceptance says so in as many words,
  /// and the reason is that a notice bar says "something failed" while the operator is
  /// looking at fifty rows. The mark has to be ON the row, because the question they are
  /// actually asking is "did MY park land", and only the row can answer it.
  final String? unsentLabel;

  const TaskRow( {
    super.key,
    required this.model,
    this.verbs = const <VerbNeeds>[],
    this.onVerb,
    this.onFieldChanged,
    this.ownerOptions = const <String>[],
    this.unsentLabel,
  } );

  @override
  State<TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<TaskRow> {
  bool _expanded = false;

  /// The verb currently armed, if any. Terminal verbs arm before they fire (§7.4).
  String? _armedVerb;

  @override
  Widget build( BuildContext context ) {
    return Column(
      crossAxisAlignment : CrossAxisAlignment.start,
      children : [
        _line1( context ),
        _line2( context ),
        // 🔴 COLLAPSED CONTROLS MUST BE ABSENT FROM THE SEMANTICS TREE, NOT MERELY
        // INVISIBLE. Under ruling 2 the disclosed row is this pane's PRIMARY VERB
        // SURFACE. Hidden with `Opacity(0)`, a zero-height `SizedBox`, or
        // `Visibility(…, maintainSemantics: true)`, TalkBack reads and can ACTIVATE
        // every row's write verbs while the row looks collapsed.
        //
        // `Visibility` drops the child from the tree by default, which is what we want —
        // and note that the two idioms a Flutter developer reaches for first
        // (`Visibility(visible:false)`, `Offstage`) are both accidentally correct here.
        // That is precisely the condition under which something drifts unnoticed later,
        // so the widget test asserts no action node is reachable while collapsed rather
        // than trusting the default.
        Visibility(
          visible : _expanded,
          child   : _line3( context ),
        ),
      ],
    );
  }

  /// Line 1 is the title and the disclosure control. Nothing else fits.
  ///
  /// At 360 dp — ordinary Android portrait — 16 dp gutters and a 48 dp minimum
  /// interactive target leave roughly 86 dp for the title, about twelve characters.
  /// Every title in this fleet shares a `[LUPIN-MOBILE] Phase N:` prefix, so packing
  /// `id · class · status · priority` here truncates every row to the SAME string and
  /// the pane cannot be read at all.
  Widget _line1( BuildContext context ) {
    return Row(
      children : [
        if ( widget.unsentLabel != null ) _unsentMark( context ),
        Expanded(
          child : _cell( 'title', widget.model.title, style: Theme.of( context ).textTheme.titleSmall ),
        ),
        _disclosureToggle( context ),
      ],
    );
  }

  /// The mark a row wears while one of the operator's writes has not landed.
  ///
  /// 🔴 ON LINE 1, WHERE THE ROW IS IDENTIFIED, AND NOT BEHIND THE DISCLOSURE. A mark
  /// hidden inside the controls answers the question only for someone who already
  /// suspects the answer. §7.2 is emphatic that line 1 does not survive extra FIELDS at
  /// 360 dp — this is an icon, not a field, and it is the one thing on the row that is
  /// about the operator rather than about the task.
  ///
  /// ⚠️ THE LABEL NAMES THE VERB, NOT THE FAILURE. "Park not sent" tells the operator
  /// what to press again; "write failed" tells them something is broken and leaves them
  /// to work out what. Colour carries none of it — `Semantics` does, because a coloured
  /// glyph is invisible to TalkBack and to anyone who does not know this app's palette.
  Widget _unsentMark( BuildContext context ) {
    return Padding(
      padding : const EdgeInsets.only( right: 6 ),
      child   : Semantics(
        label : '${widget.unsentLabel} — not sent',
        child : Icon(
          Icons.cloud_off,
          key   : const Key( TestKeys.taskRowUnsentMark ),
          size  : 16,
          color : Theme.of( context ).colorScheme.error,
        ),
      ),
    );
  }

  Widget _line2( BuildContext context ) {
    final cells = RowSchema.line2
        .map( ( c ) => _cell( c.key, widget.model.cell( c.key ) ) )
        .toList( growable: false );

    // Wrap rather than Row: nine fields do not fit one phone line either, and a
    // hard-coded break point would be another number that goes stale silently.
    return Wrap( spacing: 8, runSpacing: 4, children: cells );
  }

  Widget _line3( BuildContext context ) {
    return Column(
      key                : const Key( TestKeys.taskRowControls ),
      crossAxisAlignment : CrossAxisAlignment.start,
      children : [
        _cell( 'detail', widget.model.cell( 'detail' ) ),
        // The FIELD door sits above the verbs, and the order is not arbitrary: priority
        // and owner are reversible edits, the verbs below include two that are not, and
        // the reversible controls should not be the ones a thumb reaches last.
        if ( widget.onFieldChanged != null ) _fieldControls( context ),
        _verbBar( context ),
      ],
    );
  }

  Widget _fieldControls( BuildContext context ) {
    return TaskFieldControls(
      priority       : widget.model.priority,
      ownerPersona   : widget.model.ownerPersona,
      ownerOptions   : widget.ownerOptions,
      onFieldChanged : widget.onFieldChanged!,
    );
  }

  /// Every cell carries its schema key, so the identity guard can read the ORDERED key
  /// list out of a rendered pane. A cell with no value still renders — an absent cell
  /// and an empty one are different, and the guard compares presence and order.
  Widget _cell( String key, String? value, { TextStyle? style } ) {
    return Text(
      value ?? '—',
      key      : Key( '${TestKeys.taskRowCellPrefix}$key' ),
      style    : style,
      maxLines : 1,
      overflow : TextOverflow.ellipsis,
    );
  }

  /// The disclosure control.
  ///
  /// ⚠️ `expanded:` CARRIES STATE, NOT PURPOSE. Without a label the toggle is a glyph
  /// and TalkBack says "button, collapsed" — the user never learns there are verbs
  /// behind it. `Semantics(expanded:)` raises `hasExpandedState`/`isExpanded`, which
  /// Android turns into "expanded"/"collapsed"; a visual rotation delivers none of it
  /// (`basic.dart:7344`, `semantics.dart:1392`, `:5401-5405`).
  ///
  /// ⚠️ This is the app's FIRST `Semantics` widget — `grep -rn 'Semantics(' lib`
  /// returned zero before this file. There is no existing practice to carry substance
  /// into; it is being set here, on the app's densest UI.
  Widget _disclosureToggle( BuildContext context ) {
    return Semantics(
      expanded : _expanded,
      label    : _expanded ? 'Hide row controls' : 'Show row controls',
      child    : IconButton(
        key       : const Key( TestKeys.taskRowDisclosure ),
        icon      : const Icon( Icons.more_horiz ),
        // The web spec is an ellipsis right-justified ON THE TITLE LINE
        // (`rowSchema.ts:12-15`); the second row is not displayed by default.
        onPressed : () => setState( () {
          _expanded = !_expanded;
          if ( !_expanded ) _armedVerb = null;   // collapsing disarms
        } ),
      ),
    );
  }

  Widget _verbBar( BuildContext context ) {
    return Wrap(
      spacing  : 8,
      children : widget.verbs.map( _verbButton ).toList( growable: false ),
    );
  }

  /// A terminal verb ARMS, then fires on the second press (`taskVerbs.ts:116-117` —
  /// `terminal: true` is the shared module's `armsTwice`). On a phone, where a mis-tap is
  /// likelier than a mis-click, this is the single most worth carrying.
  ///
  /// 🔴 AND CARRYING IT AS WRITTEN PROTECTS A SIGHTED USER AND NOBODY ELSE. In Flutter,
  /// CHANGING A BUTTON'S LABEL IN PLACE IS NOT ANNOUNCED — TalkBack focus stays on the
  /// node, the text under it changes, and nothing is spoken (`semantics.dart:5351-5362`:
  /// an update is announced only with `liveRegion`, *"even if the widget does not have
  /// accessibility focus"*). A TalkBack user believes the first tap missed and taps
  /// again — AND THAT IS THE TAP THAT FIRES THE TERMINAL ACTION. A safety mechanism that
  /// makes a mis-tap harder for one class of user and no harder for another, recorded as
  /// handled, is strictly worse than omitting it.
  ///
  /// ⇒ The armed state is a LIVE REGION, and the test asserts the ANNOUNCEMENT rather
  /// than the label change.
  ///
  /// ⚠️ Do not reach for `SemanticsService.announce` — it is deprecated on Android
  /// (`semantics_service.dart:40-46`), with the SDK itself pointing at `liveRegion`.
  Widget _verbButton( VerbNeeds verb ) {
    final armed = _armedVerb == verb.name;
    final label = armed ? 'Confirm ${verb.name}' : verb.name;

    // ⚠️ THE FLAG MUST SIT ON THE NODE THAT CARRIES THE LABEL, OR IT ANNOUNCES NOTHING.
    // A bare `Semantics( liveRegion: … )` around a button produces a SEPARATE node with
    // no label of its own, and the button's changing text stays on the child node —
    // so the live region fires on a node that says nothing while the words the user
    // needs change silently one level down. `MergeSemantics` folds them into one node
    // that has both the label and the flag. Caught by the test below, which asserts the
    // flag on the node the button key resolves to.
    return MergeSemantics(
      child : Semantics(
        liveRegion : armed,
        child      : TextButton(
          key       : Key( '${TestKeys.taskRowVerbPrefix}${verb.name}' ),
          onPressed : () => _pressVerb( verb, armed ),
          child     : Text( label ),
        ),
      ),
    );
  }

  /// One press of a verb button: arm, or collect, or fire.
  ///
  /// 🔴 ARMING COMES FIRST AND THE SHEET COMES SECOND, NOT THE OTHER WAY ROUND. §7.4's
  /// mechanism is that a terminal verb's FIRST tap changes nothing and says so out loud
  /// (the live region). Opening the sheet on that first tap would put a modal in front of
  /// the announcement, and a TalkBack user would meet the sheet instead of the warning —
  /// which is the failure §7.4 exists to prevent, wearing a different costume.
  ///
  /// ⚠️ THE ROW STAYS DISARMED AFTER THE SHEET, EVEN WHEN THE OPERATOR CANCELS. Leaving
  /// a terminal verb armed behind a dismissed sheet means the NEXT tap fires it with no
  /// warning at all — the operator backed out, and a back-out that leaves the safety off
  /// is worse than no safety.
  ///
  /// Ensures:
  ///   - a terminal verb that is not yet armed only arms, and sends nothing
  ///   - a verb needing nothing fires immediately with its payload
  ///   - a verb needing a reason or a date opens the shared sheet, and fires only if the
  ///     sheet returns a complete payload
  Future<void> _pressVerb( VerbNeeds verb, bool armed ) async {
    if ( verb.terminal && !armed ) {
      setState( () => _armedVerb = verb.name );
      return;
    }
    setState( () => _armedVerb = null );

    if ( !verb.needsSheet ) {
      widget.onVerb?.call( buildTaskVerb( verb.name ) );
      return;
    }

    final built = await showVerbReasonSheet(
      context,
      needs    : verb,
      rowTitle : widget.model.title,
    );
    if ( built == null ) return;   // cancelled — no write, and the verb is disarmed
    widget.onVerb?.call( built );
  }
}
