import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../data/task_row_model.dart';
import '../data/task_row_schema.dart';
import '../data/task_verbs.dart';
import '../data/task_write_repository.dart';
import 'task_field_controls.dart';
import 'verb_reason_sheet.dart';

/// The one row widget; Task List and Holding Area render it with identical cells.
///
/// It has no pane parameter, and that absence is what keeps the panes identical. A
/// `pane: Pane.holdingArea` argument with `if ( pane == ... )` branches in `build` would
/// share a type and none of the cell-for-cell identity. The constructor takes a row model
/// and nothing that says which pane it is in. What one pane needs and its sibling does
/// not, such as the Holding Area's batch selection, lives in the group header or a wrapper.
/// Drift then needs a constructor change, which shows up in review.
///
/// Finished Tasks must not render this widget: its rows come from `task_events` and carry
/// no `priority`, `blocked`, `accountable` or `actions`. A guard test asserts it does not.
class TaskRow extends StatefulWidget {
  /// The row to render.
  final TaskRowModel model;

  /// The verbs this row offers, as obligations rather than built payloads.
  ///
  /// The pane says which verbs, as data; both panes may pass the same list. The row
  /// collects what each verb needs through the shared sheet. It hands the pane a complete
  /// payload. Built payloads would not work. Four of the seven verbs need a reason the
  /// operator has not yet typed. Building them eagerly would send an empty reason and get
  /// a 422 on every press.
  final List<VerbNeeds> verbs;

  /// Called when the operator confirms a verb and has supplied everything it requires.
  ///
  /// The row owns arming and the sheet; the pane owns the write and the optimistic rollback.
  final void Function( TaskVerb verb )? onVerb;

  /// Called when the operator commits a field change, priority or owner, never status.
  ///
  /// Null means the pane offers no field edits. That is data, not a pane discriminator,
  /// like [onVerb]: the controls appear because their output has somewhere to go.
  final void Function( { String? priority, String? ownerPersona } )? onFieldChanged;

  /// The personas this row may be reassigned to, from the live fleet.
  final List<String> ownerOptions;

  /// What the operator did to this row that has not reached the server, or null.
  ///
  /// It is visible state on the row, not only a notice. A notice bar says something failed
  /// while the operator looks at fifty rows. The question they ask is whether their own
  /// park landed, and only the row can answer it.
  final String? unsentLabel;

  /// Creates a row; [verbs], [onVerb] and [onFieldChanged] are supplied by the pane.
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

  // The verb currently armed, if any. Terminal verbs arm before they fire.
  String? _armedVerb;

  @override
  Widget build( BuildContext context ) {
    return Column(
      crossAxisAlignment : CrossAxisAlignment.start,
      children : [
        _line1( context ),
        _line2( context ),
        // Collapsed controls must be absent from the semantics tree, not merely invisible.
        // The disclosed row is the pane's primary verb surface. Hidden with `Opacity(0)`,
        // a zero-height `SizedBox` or `Visibility(..., maintainSemantics: true)`, TalkBack
        // can read and activate every row's write verbs while the row looks collapsed.
        // `Visibility` drops the child from the tree by default, as does `Offstage`, so the
        // default is correct here. The widget test asserts that no action node is reachable
        // while collapsed, instead of trusting the default.
        Visibility(
          visible : _expanded,
          child   : _line3( context ),
        ),
      ],
    );
  }

  // Line 1 is the title and the disclosure control; nothing else fits. At 360 dp, 16 dp
  // gutters and a 48 dp target leave roughly 86 dp for the title, about twelve characters.
  // Fleet titles share a `[LUPIN-MOBILE] Phase N:` prefix, so more fields here would
  // truncate every row to the same string.
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

  // The mark a row wears while one of the operator's writes has not landed. It sits on
  // line 1, where the row is identified, not behind the disclosure, because a mark hidden
  // in the controls helps only someone who already suspects the answer. It is an icon, not
  // a field, so it does not crowd line 1. The label names the verb ("Park not sent"), which
  // tells the operator what to press again, where "write failed" would not. `Semantics`
  // carries the label and colour carries nothing, because TalkBack cannot see a coloured
  // glyph.
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

    // A Wrap, not a Row: nine fields do not fit one phone line, and a hard-coded break
    // point would go stale silently.
    return Wrap( spacing: 8, runSpacing: 4, children: cells );
  }

  Widget _line3( BuildContext context ) {
    return Column(
      key                : const Key( TestKeys.taskRowControls ),
      crossAxisAlignment : CrossAxisAlignment.start,
      children : [
        _cell( 'detail', widget.model.cell( 'detail' ) ),
        // The field controls sit above the verbs. Priority and owner are reversible, the
        // verbs below include two that are not, and reversible controls should not be the
        // ones a thumb reaches last.
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

  // Every cell carries its schema key, so the identity guard can read the ordered key
  // list out of a rendered pane. A cell with no value still renders as a dash, because the
  // guard compares presence and order, and an absent cell differs from an empty one.
  Widget _cell( String key, String? value, { TextStyle? style } ) {
    return Text(
      value ?? '—',
      key      : Key( '${TestKeys.taskRowCellPrefix}$key' ),
      style    : style,
      maxLines : 1,
      overflow : TextOverflow.ellipsis,
    );
  }

  // The disclosure control. `expanded:` carries state, not purpose: without a label the
  // toggle is a bare glyph and TalkBack says only "button, collapsed", so the user never
  // learns that verbs sit behind it. `Semantics(expanded:)` sets the expanded state that
  // Android announces as "expanded" or "collapsed"; a visual rotation announces nothing.
  Widget _disclosureToggle( BuildContext context ) {
    return Semantics(
      expanded : _expanded,
      label    : _expanded ? 'Hide row controls' : 'Show row controls',
      child    : IconButton(
        key       : const Key( TestKeys.taskRowDisclosure ),
        icon      : const Icon( Icons.more_horiz ),
        // The web spec puts an ellipsis, right-justified, on the title line; the second
        // row is hidden by default.
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

  // A terminal verb arms on the first press and fires on the second, which is the shared
  // module's `armsTwice`. On a phone a mis-tap is likelier than a mis-click.
  //
  // Changing a button's label in place is not announced in Flutter. TalkBack focus stays
  // on the node, the text changes and nothing is spoken, because an update is announced
  // only with `liveRegion`. A TalkBack user then believes the first tap missed and taps
  // again, and that tap fires the terminal action. So the armed state is a live region,
  // and the test asserts the announcement, not the label change. Do not use
  // `SemanticsService.announce`: it is deprecated on Android in favour of `liveRegion`.
  Widget _verbButton( VerbNeeds verb ) {
    final armed = _armedVerb == verb.name;
    final label = armed ? 'Confirm ${verb.name}' : verb.name;

    // The live-region flag must sit on the node that carries the label, or it announces
    // nothing. A bare `Semantics( liveRegion: ... )` around a button makes a separate node
    // with no label, while the changing text stays on the child node. `MergeSemantics`
    // folds them into one node holding both. The widget test asserts the flag on the node
    // the button key resolves to.
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

  /// Handles one press of a verb button: arm, collect, or fire.
  ///
  /// Arming comes before the sheet: the first tap on a terminal verb only announces,
  /// and a sheet opened then would cover the announcement. The row stays disarmed after
  /// the sheet, even on cancel, or the next tap would fire with no warning.
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
    if ( built == null ) return;   // cancelled: no write, and the verb stays disarmed
    widget.onVerb?.call( built );
  }
}
