import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../data/holding_area_models.dart';

/// One persona's group header: the disclosure control, and that group's two batch
/// controls.
///
/// 🔴 THIS *WAS* NOT AN ACCORDION HEADER, AND RICK OVERRULED THAT ON 2026-09-22. The old
/// note argued from the web — `notifications.js:14085`, *"IT IS NOT AN ACCORDION
/// LISTENER"* — and concluded that a toggle here *"would invent a state the pane does not
/// have and hide held rows behind a gesture, in the pane whose entire job is showing what
/// is still held."* He asked for the gesture anyway, having noted that neither existing
/// client has it: *"I want them displayed folded by default so that we can do progressive
/// disclosure."*
///
/// 🔴 SO THE OLD NOTE'S HAZARD IS REAL AND IS ANSWERED HERE RATHER THAN DISMISSED:
/// **FOLDING MUST NOT HIDE HOW MUCH IS HELD.** A collapsed group and an empty one must
/// not read alike, or the operator approves blind. Three things therefore stay on screen
/// while folded — the persona, the count, and BOTH batch controls with the count inside
/// their labels — and the count is in the semantic label too, so TalkBack hears it
/// without unfolding.
///
/// ⚠️ THE REASON BOX IS THE ONE THING THAT FOLDS AWAY WITH THE ROWS, and that leaves a
/// hole the bloc closes rather than this widget: won't-fix-all on a folded group sets a
/// complaint about a field that is off screen, so the bloc unfolds the group at the same
/// time it sets the complaint. See `_onWontFixAll`.
///
/// ⚠️ EVERYTHING THAT DISTINGUISHES THIS PANE FROM THE TASK LIST LIVES HERE RATHER THAN
/// IN THE ROW. `TaskRow` takes no pane discriminator (§7); batch selection is the
/// Holding Area's alone, so it belongs to the header that owns the group.
class FilerGroupHeader extends StatefulWidget {
  final FilerGroup group;

  /// Whether this persona's rows are on screen. Folded is the default — the pane keeps
  /// the set, so the header stays a pure function of what it is handed.
  final bool expanded;

  /// Fold or unfold this persona's rows.
  final VoidCallback onToggle;

  /// The reason currently typed for this group.
  final String reason;

  /// The complaint to show under the box, or null.
  final String? reasonError;

  /// True while this group's batch write is in flight — both controls go inert.
  final bool busy;

  final ValueChanged<String> onReasonChanged;

  /// Fired only AFTER the operator answers the confirm.
  final VoidCallback onApproveAll;

  final VoidCallback onWontFixAll;

  /// What TalkBack reads for the disclosure control.
  ///
  /// 🔴 THE COUNT IS IN THE LABEL, AND THAT IS THE PART THAT CARRIES THE SAFETY. A
  /// collapsed group and an empty one announce identically without it, so a screen-reader
  /// user is told a persona has held work only by unfolding every one of them. The
  /// sighted reader gets the same fact from the number beside the name and from both
  /// button labels; this is that reader's copy.
  ///
  /// Kept as a static so the test asserts the SAME string the widget renders rather than
  /// a copy that can drift from it.
  static String semanticLabel( String filer, int count ) =>
      '$filer, $count held ${count == 1 ? 'row' : 'rows'}';

  /// Where the persona label's text starts: 16 dp gutter + 20 dp chevron + 8 dp gap.
  /// Derived from the three numbers rather than typed as 44, so it moves with them.
  static const double _gutter      = 16;
  static const double _chevronSize = 20;
  static const double _chevronGap  = 8;
  static const double textInset    = _gutter + _chevronSize + _chevronGap;

  const FilerGroupHeader( {
    super.key,
    required this.group,
    required this.reason,
    required this.onReasonChanged,
    required this.onApproveAll,
    required this.onWontFixAll,
    required this.onToggle,
    this.expanded = false,
    this.reasonError,
    this.busy = false,
  } );

  @override
  State<FilerGroupHeader> createState() => _FilerGroupHeaderState();
}

class _FilerGroupHeaderState extends State<FilerGroupHeader> {
  /// 🔴 THE CONTROLLER IS OWNED BY THE STATE, NOT BUILT IN `build`.
  /// `TextEditingController.fromValue( … )` inside `build` is the idiom that looks
  /// correct and is not: a fresh controller on every rebuild, and this widget rebuilds
  /// on every keystroke because the text it renders lives in the bloc. The visible
  /// symptom is a caret that jumps to the end — in the one box on this pane the operator
  /// has to type a sentence into.
  late final TextEditingController _reason;

  FilerGroup get group => widget.group;

  @override
  void initState() {
    super.initState();
    _reason = TextEditingController( text: widget.reason );
  }

  /// Accept text pushed in from outside — a batch that cleared the box on success — but
  /// never re-assert what the operator is already typing, which would fight the caret.
  @override
  void didUpdateWidget( FilerGroupHeader old ) {
    super.didUpdateWidget( old );
    if ( widget.reason != _reason.text ) {
      _reason.value = TextEditingValue(
        text      : widget.reason,
        selection : TextSelection.collapsed( offset: widget.reason.length ),
      );
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build( BuildContext context ) {
    return Padding(
      key     : Key( '${TestKeys.holdingGroupHeaderPrefix}${group.filer}' ),
      padding : const EdgeInsets.symmetric( horizontal: 16, vertical: 8 ),
      child   : Column(
        crossAxisAlignment : CrossAxisAlignment.start,
        children : [
          _title( context ),
          const SizedBox( height: 8 ),
          // 🔴 ABSENT FROM THE TREE WHILE FOLDED, NOT MERELY INVISIBLE. `Visibility`
          // drops the child by default, which is what we want: a `TextField` hidden with
          // `Opacity(0)` or `maintainSemantics: true` is still focusable and still
          // typable under TalkBack, so a screen-reader user would be editing the
          // justification for a batch whose rows are folded out of sight.
          Visibility(
            visible : widget.expanded,
            child   : Column(
              crossAxisAlignment : CrossAxisAlignment.start,
              children : [
                _reasonBox( context ),
                const SizedBox( height: 8 ),
              ],
            ),
          ),
          _batchControls( context ),
        ],
      ),
    );
  }

  /// The persona, the count, and the fold control — one tap target.
  ///
  /// 🔴 THE WHOLE HEADING IS THE TARGET, NOT JUST THE CHEVRON. A 20 dp glyph is under
  /// half the 48 dp floor, and a fold aimed at one persona that lands on the next one
  /// HIDES ROWS rather than merely missing. `kMinInteractiveDimension` is the floor
  /// itself, as a constraint — padding is a number someone picks and a font change moves
  /// back under the line silently.
  ///
  /// The count also rides INSIDE both button labels. That is deliberate duplication: the
  /// web prints it once, in a span beside the name, so the operator reads the blast
  /// radius somewhere other than on the control they are about to press.
  Widget _title( BuildContext context ) {
    return Semantics(
      button   : true,
      expanded : widget.expanded,
      label    : FilerGroupHeader.semanticLabel( group.filer, group.count ),
      // The child's own text would otherwise be announced again after the label above.
      child    : ExcludeSemantics(
        child : InkWell(
          key   : Key( '${TestKeys.holdingGroupTogglePrefix}${group.filer}' ),
          onTap : widget.onToggle,
          child : ConstrainedBox(
            constraints : const BoxConstraints( minHeight: kMinInteractiveDimension ),
            child : Row(
              children : [
                Icon(
                  widget.expanded ? Icons.expand_more : Icons.chevron_right,
                  size : FilerGroupHeader._chevronSize,
                ),
                const SizedBox( width: FilerGroupHeader._chevronGap ),
                Expanded(
                  child : Text(
                    '${group.filer} · ${group.count}',
                    style    : Theme.of( context ).textTheme.titleSmall,
                    maxLines : 1,
                    overflow : TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The batch reason box.
  ///
  /// 🔴 A BOX, NOT A DIALOG, AND THE WEB REJECTED THE DIALOG DELIBERATELY: a `confirm()`
  /// blocks the event loop. The phone reason is different and points the same way — the
  /// operator has to be able to read the group they are about to close WHILE typing the
  /// justification for closing it, which a modal takes away.
  ///
  /// ⚠️ IT IS ALWAYS PRESENT, NOT REVEALED BY PRESSING WON'T-FIX-ALL. Revealing it on
  /// press turns one deliberate act into two taps and a surprise, and — worse — makes the
  /// requirement discoverable only by triggering the thing it is guarding.
  Widget _reasonBox( BuildContext context ) {
    return TextField(
      key        : Key( '${TestKeys.holdingReasonFieldPrefix}${group.filer}' ),
      enabled    : !widget.busy,
      controller : _reason,
      onChanged  : widget.onReasonChanged,
      minLines   : 1,
      maxLines   : 3,
      decoration : InputDecoration(
        labelText : kHoldingWontFixReasonLabel,
        hintText  : kHoldingWontFixReasonPlaceholder,
        // ⚠️ `errorText` RATHER THAN A KEYED `Text` BELOW THE FIELD. It is what Flutter
        // wires into the field's own semantics, so TalkBack reads the complaint as part
        // of the box instead of as a stray sentence the user has to go find. The test
        // reads it off the widget's decoration — a typed assertion, not a string search
        // over the tree, so it cannot pass against a label that merely contains it.
        errorText : widget.reasonError,
        border    : const OutlineInputBorder(),
        isDense   : true,
      ),
    );
  }

  /// Approve-all and won't-fix-all.
  ///
  /// 🔴 THEY MUST NOT SIT ADJACENT AND IDENTICALLY DRESSED. One is reversible and one is
  /// terminal, and two same-shaped buttons a thumb's width apart is how a terminal batch
  /// gets pressed by the hand aiming at the reversible one. Approve-all is the filled
  /// button; won't-fix-all is outlined, in the error colour, and separated.
  ///
  /// ⚠️ `Wrap`, NOT `Row`. At 360 dp — ordinary Android portrait — two 48 dp-tall
  /// buttons carrying "Approve (14)" and "Won't fix all (14)" do not share a line with
  /// 16 dp gutters. A `Row` would overflow, and an overflow here clips the label that
  /// carries the count.
  Widget _batchControls( BuildContext context ) {
    final scheme = Theme.of( context ).colorScheme;

    return Wrap(
      spacing    : 24,     // wider than the 8 dp used elsewhere: these two are not peers
      runSpacing : 8,
      children   : [
        _approveAll( context ),
        _named(
          hint  : holdingWontFixAllHint( group.filer ),
          child : OutlinedButton(
            key       : Key( '${TestKeys.holdingWontFixAllPrefix}${group.filer}' ),
            onPressed : widget.busy ? null : widget.onWontFixAll,
            style     : OutlinedButton.styleFrom(
              foregroundColor : scheme.error,
              side            : BorderSide( color: scheme.error ),
              minimumSize     : const Size( 0, kMinInteractiveDimension ),
            ),
            child : Text( batchLabel( "Won't fix all", group.count ) ),
          ),
        ),
      ],
    );
  }

  /// Approve-all, behind its confirm.
  ///
  /// 🔴 THE CONFIRM IS RICK'S RULING AND IT IS ON THE REVERSIBLE VERB, WHICH READS
  /// BACKWARDS UNTIL YOU COUNT THE GATES. Won't-fix-all is already gated — by a required
  /// reason box the operator must type into before it will fire. Approve-all needed no
  /// typing at all, so it had no gate, and its blast radius is every held row in the
  /// group in one press.
  Widget _approveAll( BuildContext context ) {
    return _named(
      hint  : holdingApproveAllHint( group.filer ),
      child : FilledButton(
        key       : Key( '${TestKeys.holdingApproveAllPrefix}${group.filer}' ),
        onPressed : widget.busy ? null : () => _confirmApproveAll( context ),
        style     : FilledButton.styleFrom(
          minimumSize : const Size( 0, kMinInteractiveDimension ),
        ),
        child : Text( batchLabel( "Approve", group.count ) ),
      ),
    );
  }

  Future<void> _confirmApproveAll( BuildContext context ) async {
    final ok = await showDialog<bool>(
      context : context,
      builder : ( dialogContext ) => AlertDialog(
        key     : const Key( TestKeys.holdingApproveAllConfirm ),
        title   : const Text( kHoldingApproveAllConfirmTitle ),
        content : Text( holdingApproveAllConfirmBody( group.filer, group.count ) ),
        actions : [
          TextButton(
            key       : const Key( TestKeys.holdingApproveAllConfirmNo ),
            onPressed : () => Navigator.of( dialogContext ).pop( false ),
            child     : const Text( kHoldingApproveAllConfirmCancel ),
          ),
          FilledButton(
            key       : const Key( TestKeys.holdingApproveAllConfirmOk ),
            onPressed : () => Navigator.of( dialogContext ).pop( true ),
            child     : Text( holdingApproveAllConfirmAccept( group.count ) ),
          ),
        ],
      ),
    );

    if ( ok == true ) widget.onApproveAll();
  }

  /// A control wearing the sentence that is its NAME.
  ///
  /// 🔴 THE HINT GOES IN THE SEMANTICS TREE, NOT IN A LONG-PRESS SHEET. On the web these
  /// are `title` attributes and a phone has no hover, so carrying the buttons across
  /// without them drops the only place either risk is explained. A long press would
  /// strand nobody — it is reachable under TalkBack — but it is a DISCOVERY gesture, and
  /// what it would hide is the only statement anywhere that approve-all is reversible
  /// and won't-fix-all is terminal.
  ///
  /// 🔴 THE HINT WRAPS THE BUTTON FROM OUTSIDE, AND THE INSIDE-OUT VERSION IS THE ONE
  /// THAT LOOKS RIGHT AND ANNOUNCES NOTHING. Putting `Semantics( label:, hint: )` around
  /// the button's CHILD puts it below the node the button itself builds; the button
  /// takes its label from the child's text, the hint stays stranded on the inner node,
  /// and `getSemantics` on the button reads an empty hint — measured, not assumed. From
  /// outside, `MergeSemantics` folds the annotation and the button's own node (label,
  /// button flag, tap action) into ONE node carrying all of it.
  Widget _named( { required String hint, required Widget child } ) {
    return MergeSemantics(
      child : Semantics( hint: hint, child: child ),
    );
  }
}
