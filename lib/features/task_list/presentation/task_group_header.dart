import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';

/// One owner group's header — the pane's SECOND disclosure surface.
///
/// 🔴 THE ROW'S ELLIPSIS HIDES VERBS; THIS HIDES ROWS. They are different surfaces with
/// different stakes, which is why this is not the row's disclosure reused. The web header
/// is `role="button" tabindex="0" aria-expanded aria-controls`
/// (`notifications.js:12010`).
///
/// 🔴 THE COUNT IS IN THE LABEL, AND THAT IS THE PART THAT MATTERS. "Collapsed" alone
/// does not tell a screen-reader user whether work is hidden or simply absent — a
/// collapsed group and an empty one announce identically, and the operator is then
/// looking at a task list with work silently missing while nothing says so.
///
/// ⚠️ THE ACCEPTANCE LINE FOR THIS WIDGET WAS REWRITTEN, AND THE REASON IS WORTH KEEPING.
/// It used to read *"group header keyboard-operable"* — which a PHONE CAN NEITHER
/// SATISFY NOR FAIL, having no keyboard. A builder could not make it true; a reviewer
/// could not make it false. Rachel caught it before it was minted. `Semantics( button:,
/// expanded:, label: )` is the phone-meaningful equivalent, and it is testable.
class TaskGroupHeader extends StatelessWidget {
  final String ownerLabel;
  final int count;
  final bool expanded;
  final VoidCallback onToggle;

  const TaskGroupHeader( {
    super.key,
    required this.ownerLabel,
    required this.count,
    required this.expanded,
    required this.onToggle,
  } );

  /// What TalkBack reads. Kept as a static so the test asserts the SAME string the
  /// widget renders rather than a copy that can drift from it.
  static String semanticLabel( String ownerLabel, int count ) =>
      '$ownerLabel, $count ${count == 1 ? 'task' : 'tasks'}';

  @override
  Widget build( BuildContext context ) {
    return Semantics(
      button   : true,
      expanded : expanded,
      label    : semanticLabel( ownerLabel, count ),
      // The child's own text would otherwise be announced again after the label above.
      child    : ExcludeSemantics(
        child : InkWell(
          key     : Key( '${TestKeys.taskListGroupHeaderPrefix}$ownerLabel' ),
          onTap   : onToggle,
          // 🔴 48 dp MINIMUM, AS A CONSTRAINT RATHER THAN TUNED PADDING. A group header
          // is a touch target like any other, and below the floor a collapse aimed at one
          // group lands on its neighbour — which HIDES ROWS, not just verbs.
          //
          // ⚠️ Measured: padding alone gave 44 dp. Padding is a number someone picks and
          // then a font or icon change moves it, silently, back under the line;
          // `kMinInteractiveDimension` is the floor itself and cannot drift away from it.
          // My own widget test caught this before it shipped.
          child   : ConstrainedBox(
            constraints : const BoxConstraints( minHeight: kMinInteractiveDimension ),
            child : Padding(
            padding : const EdgeInsets.symmetric( vertical: 12, horizontal: 16 ),
            child   : Row(
              children : [
                Icon( expanded ? Icons.expand_more : Icons.chevron_right, size: 20 ),
                const SizedBox( width: 8 ),
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
