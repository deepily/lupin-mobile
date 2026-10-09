import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../data/holding_area_models.dart';
import '../../../shared/widgets/dictation_text_field.dart';

/// Header of one persona's group: the fold control and the two batch controls.
///
/// Folding must not hide how much is held, so the persona, the count and both batch
/// controls stay on screen while folded. The count is also in the semantic label.
/// Design: src/docs/decisions/README.md (R-HA-accordion)
///
/// The reason box folds away with the rows. Won't-fix-all on a folded group sets a
/// complaint on that hidden field, so the bloc unfolds the group (`_onWontFixAll`).
/// Pane-specific behaviour lives here, not in `TaskRow`, which takes no pane flag.
class FilerGroupHeader extends StatefulWidget {
  /// The persona group this header controls.
  final FilerGroup group;

  /// Whether this persona's rows are on screen; the pane keeps the set, default folded.
  final bool expanded;

  /// Called to fold or unfold this persona's rows.
  final VoidCallback onToggle;

  /// The reason currently typed for this group's batch won't-fix.
  final String reason;

  /// The complaint shown under the reason box, or null for none.
  final String? reasonError;

  /// True while this group's batch write is in flight; both batch buttons are disabled.
  final bool busy;

  /// Called with the new text when the operator edits the reason box.
  final ValueChanged<String> onReasonChanged;

  /// Called only after the operator accepts the approve-all confirm.
  final VoidCallback onApproveAll;

  /// Called when the operator presses won't-fix-all.
  final VoidCallback onWontFixAll;

  /// What a screen reader announces for the disclosure control, including the row count.
  ///
  /// Without the count a folded group and an empty one sound the same. It is static so
  /// the test asserts the string the widget renders.
  static String semanticLabel( String filer, int count ) =>
      '$filer, $count held ${count == 1 ? 'row' : 'rows'}';

  static const double _gutter      = 16;
  static const double _chevronSize = 20;
  static const double _chevronGap  = 8;
  /// Left inset of the persona label, in dp.
  ///
  /// Sum of the 16 dp gutter, 20 dp chevron and 8 dp gap, so it follows the three.
  static const double textInset    = _gutter + _chevronSize + _chevronGap;

  /// Creates a header for [group]; it is folded unless [expanded] is true.
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
  // Owned by the state, not built in `build`. A controller created on every rebuild
  // makes the caret jump to the end, and this widget rebuilds on every keystroke.
  late final TextEditingController _reason;

  FilerGroup get group => widget.group;

  @override
  void initState() {
    super.initState();
    _reason = TextEditingController( text: widget.reason );
  }

  // Accepts text pushed in from outside, such as a cleared box after a successful batch.
  // It never re-asserts text the operator is typing, which would fight the caret.
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
          // Absent from the tree while folded. `Visibility` drops its child by default; a
          // field hidden with `Opacity(0)` or `maintainSemantics` stays focusable and
          // typable under a screen reader.
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

  // The persona, the count and the fold control as one tap target. A 20 dp chevron is
  // under half the 48 dp floor, so the whole heading is the target and
  // `kMinInteractiveDimension` is its minimum height. The count also appears in both
  // button labels, so it is not read only beside the name.
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

  // The batch reason box. It is a box, not a dialog, so the operator can read the group
  // while typing the justification. It is always present while the group is unfolded, so
  // the requirement is visible before won't-fix-all is pressed.
  Widget _reasonBox( BuildContext context ) {
    return DictationTextField(
      fieldKey   : Key( '${TestKeys.holdingReasonFieldPrefix}${group.filer}' ),
      enabled    : !widget.busy,
      controller : _reason,
      onChanged  : widget.onReasonChanged,
      minLines   : 1,
      maxLines   : 3,
      decoration : InputDecoration(
        labelText : kHoldingWontFixReasonLabel,
        hintText  : kHoldingWontFixReasonPlaceholder,
        // `errorText` is wired into the field's own semantics, so a screen reader reads the
        // complaint as part of the box. The test reads it from the decoration.
        errorText : widget.reasonError,
        border    : const OutlineInputBorder(),
        isDense   : true,
      ),
    );
  }

  // Approve-all and won't-fix-all. One is reversible and one is terminal, so they are
  // not dressed alike: approve-all is filled, won't-fix-all is outlined in the error
  // colour. `Wrap` keeps both labels whole at 360 dp, where a `Row` would overflow.
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

  // Approve-all, behind a confirm. Won't-fix-all is gated by its required reason box,
  // approve-all needs no typing, and its blast radius is every held row in the group.
  // Design: src/docs/decisions/README.md (R-HA-confirm)
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

  // Gives a control its hint through the semantics tree, since a phone has no hover for
  // a `title`. The hint wraps the button from outside: `Semantics( hint: )` on the
  // button's child stays on an inner node and the button announces none. `MergeSemantics`
  // folds the hint and the button's own node into one.
  Widget _named( { required String hint, required Widget child } ) {
    return MergeSemantics(
      child : Semantics( hint: hint, child: child ),
    );
  }
}
