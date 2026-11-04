import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';

/// One owner group's header, the pane's second disclosure surface.
///
/// The row's ellipsis hides verbs and this hides rows, so it is not the row's disclosure
/// reused. The count is in the label. "Collapsed" alone does not tell a screen-reader user
/// whether work is hidden or absent, since a collapsed group and an empty one would
/// announce identically. `Semantics( button:, expanded:, label: )` is the phone-meaningful
/// form of a keyboard-operable header, and it is testable.
class TaskGroupHeader extends StatelessWidget {
  /// The owner label, or "Unassigned".
  final String ownerLabel;

  /// How many rows the group holds.
  final int count;

  /// True when the group's rows are shown.
  final bool expanded;

  /// Called when the header is tapped.
  final VoidCallback onToggle;

  /// Creates the header.
  const TaskGroupHeader( {
    super.key,
    required this.ownerLabel,
    required this.count,
    required this.expanded,
    required this.onToggle,
  } );

  static const double _gutter      = 16;
  static const double _chevronSize = 20;
  static const double _chevronGap  = 8;

  /// Where the owner label's text starts: gutter, chevron and gap together.
  ///
  /// The pane indents its rows by exactly this, so rows sit under the persona that owns
  /// them. It is derived from the three sizes above, so it moves with them.
  static const double textInset    = _gutter + _chevronSize + _chevronGap;

  /// What TalkBack reads, as a static so the test asserts the string the widget renders.
  static String semanticLabel( String ownerLabel, int count ) =>
      '$ownerLabel, $count ${count == 1 ? 'task' : 'tasks'}';

  @override
  Widget build( BuildContext context ) {
    return Semantics(
      button   : true,
      expanded : expanded,
      label    : semanticLabel( ownerLabel, count ),
      // The child's own text would otherwise be announced again after the label.
      child    : ExcludeSemantics(
        child : InkWell(
          key     : Key( '${TestKeys.taskListGroupHeaderPrefix}$ownerLabel' ),
          onTap   : onToggle,
          // A 48 dp minimum, as a constraint and not tuned padding. Below the floor a
          // collapse aimed at one group lands on its neighbour, which hides rows. Padding
          // alone gave 44 dp, and a font or icon change would silently move it back under
          // the line; `kMinInteractiveDimension` is the floor itself.
          child   : ConstrainedBox(
            constraints : const BoxConstraints( minHeight: kMinInteractiveDimension ),
            child : Padding(
            padding : const EdgeInsets.symmetric( vertical: 12, horizontal: _gutter ),
            child   : Row(
              children : [
                Icon( expanded ? Icons.expand_more : Icons.chevron_right, size: _chevronSize ),
                const SizedBox( width: _chevronGap ),
                Expanded(
                  child : Text(
                    ownerLabel,
                    style    : Theme.of( context ).textTheme.titleSmall,
                    maxLines : 1,
                    overflow : TextOverflow.ellipsis,
                  ),
                ),
                Text( '$count' ),
              ],
            ),
            ),
          ),
        ),
      ),
    );
  }
}
