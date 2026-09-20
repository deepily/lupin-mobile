import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../data/holding_area_models.dart';

/// One filer's block header, with that group's two batch controls.
///
/// 🔴 THIS IS NOT AN ACCORDION HEADER, AND THE DIFFERENCE IS NOT COSMETIC. The web says
/// so in as many words — `notifications.js:14085`, *"IT IS NOT AN ACCORDION LISTENER"*.
/// The Task List's group header collapses; this one does not, so it exposes no toggle,
/// no `Semantics( expanded: )`, and no tap target on the header itself. Giving it one to
/// match its sibling would invent a state the pane does not have and hide held rows
/// behind a gesture — in the pane whose entire job is showing what is still held.
///
/// ⚠️ EVERYTHING THAT DISTINGUISHES THIS PANE FROM THE TASK LIST LIVES HERE RATHER THAN
/// IN THE ROW. `TaskRow` takes no pane discriminator (§7); batch selection is the
/// Holding Area's alone, so it belongs to the header that owns the group.
class FilerGroupHeader extends StatefulWidget {
  final FilerGroup group;

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

  const FilerGroupHeader( {
    super.key,
    required this.group,
    required this.reason,
    required this.onReasonChanged,
    required this.onApproveAll,
    required this.onWontFixAll,
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
          _reasonBox( context ),
          const SizedBox( height: 8 ),
          _batchControls( context ),
        ],
      ),
    );
  }

  /// The filer and the count.
  ///
  /// The count also rides INSIDE both button labels. That is deliberate duplication: the
  /// web prints it once, in a span beside the name, so the operator reads the blast
  /// radius somewhere other than on the control they are about to press.
  Widget _title( BuildContext context ) {
    return Text(
      '${group.filer} · ${group.count}',
      style    : Theme.of( context ).textTheme.titleSmall,
      maxLines : 1,
      overflow : TextOverflow.ellipsis,
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
