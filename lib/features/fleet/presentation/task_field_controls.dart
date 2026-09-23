import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';

/// The two FIELD-door controls: priority and owner.
///
/// 🔴 THESE ARE THE OTHER DOOR, AND CONFUSING THEM IS §4.2's NAMED FAILURE. Priority and
/// owner go through `PATCH /api/tasks/{id}` — exactly two keys, and `status` is not one
/// of them. A builder implementing a status change here would get a field door that
/// SILENTLY IGNORES the unknown key: a control that looks wired and changes nothing.
/// `TaskWriteRepository.patchFields` physically cannot send `status`, and this widget
/// physically cannot ask it to — it reports a priority and an owner, never a status.
///
/// ⚠️ NO PANE PARAMETER, for the third time in this feature and for the same reason. The
/// roster and the current values arrive as DATA; both task panes may pass the same ones.
class TaskFieldControls extends StatefulWidget {
  /// The row's painted priority, or null when it carries none.
  final String? priority;

  /// The row's painted owner, or null when unassigned.
  final String? ownerPersona;

  /// The personas this row may be reassigned to. Empty is a legitimate state — see
  /// `activeReassignTargets`: the phone cannot always see the fleet.
  final List<String> ownerOptions;

  /// Fired when the operator commits a change. Exactly one of the two is non-null.
  final void Function( { String? priority, String? ownerPersona } ) onFieldChanged;

  const TaskFieldControls( {
    super.key,
    required this.onFieldChanged,
    this.priority,
    this.ownerPersona,
    this.ownerOptions = const <String>[],
  } );

  @override
  State<TaskFieldControls> createState() => _TaskFieldControlsState();
}

/// The priorities an operator may choose, in rank order (`taskListModel.ts:159`).
const List<String> kEditablePriorities = <String>[ 'P0', 'P1', 'P2', 'P3', 'P4', 'P5' ];

class _TaskFieldControlsState extends State<TaskFieldControls> {
  /// The priority the operator has CHOSEN but not yet sent. Null means "same as
  /// painted".
  String? _stagedPriority;

  @override
  void didUpdateWidget( TaskFieldControls old ) {
    super.didUpdateWidget( old );
    // 🔴 A POLL THAT REPAINTS THE ROW MUST NOT STRAND A STAGED EDIT AS A PHANTOM. If the
    // painted priority has caught up with what the operator staged — their own Update
    // landed, or somebody else made the same change — the staging is spent and Update
    // goes back to disabled. Comparing against the PAINTED value is the web's rule
    // (`data-original`) for exactly this reason: the row survives the repaint, in-widget
    // memory of "what it used to be" does not.
    if ( old.priority != widget.priority && _stagedPriority == widget.priority ) {
      _stagedPriority = null;
    }
  }

  String? get _chosenPriority => _stagedPriority ?? widget.priority;

  /// 🔴 UPDATE STAYS DISABLED UNTIL THE VALUE ACTUALLY MOVES. Rick, on the classic page:
  /// *"the update button would only be enabled if I had chosen a different value to
  /// update."* A live Update on an untouched row is a button whose press asserts nothing
  /// and still burns a round trip — and, on a metered phone connection, one the operator
  /// paid for.
  bool get _priorityMoved =>
      _stagedPriority != null && _stagedPriority != widget.priority;

  @override
  Widget build( BuildContext context ) {
    // `Wrap`, not `Row`. At 360 dp two dropdowns and a button do not share a line with
    // 16 dp gutters, and an overflow here clips the control rather than wrapping it.
    return Wrap(
      spacing    : 12,
      runSpacing : 8,
      crossAxisAlignment : WrapCrossAlignment.center,
      children : [
        _priorityDropdown( context ),
        _updateButton( context ),
        _ownerDropdown( context ),
      ],
    );
  }

  /// The priority choices: the editable ranks, plus the row's own value when the store
  /// holds something this list does not know.
  ///
  /// ⚠️ AN UNRECOGNISED STORED PRIORITY GETS ITS OWN ENTRY RATHER THAN BEING SHOWN AS
  /// SOMETHING IT IS NOT. A row carrying `P9` rendered as `P0` is a lie the operator
  /// cannot see through, and pressing Update would then "correct" a value nobody chose.
  List<String> get _priorityChoices {
    final current = ( widget.priority ?? '' ).trim();
    if ( current.isEmpty || kEditablePriorities.contains( current ) ) {
      return kEditablePriorities;
    }
    return <String>[ current, ...kEditablePriorities ];
  }

  Widget _priorityDropdown( BuildContext context ) {
    return DropdownButton<String>(
      key   : const Key( TestKeys.taskFieldPriority ),
      value : _chosenPriority,
      hint  : const Text( '—' ),
      // The accessible name, because a bare dropdown announces only its value and a row
      // carries two of them.
      items : _priorityChoices
          .map( ( p ) => DropdownMenuItem<String>( value: p, child: Text( p ) ) )
          .toList( growable: false ),
      onChanged : ( chosen ) => setState( () => _stagedPriority = chosen ),
    );
  }

  Widget _updateButton( BuildContext context ) {
    return Semantics(
      label : _priorityMoved
          ? 'Update priority'
          : 'Update priority — choose a different priority to enable',
      child : OutlinedButton(
        key       : const Key( TestKeys.taskFieldPriorityUpdate ),
        onPressed : _priorityMoved
            ? () {
                widget.onFieldChanged( priority: _stagedPriority );
                // The staging is spent. It is NOT cleared to null here — the poll that
                // follows the write repaints the row, and `didUpdateWidget` retires it
                // once the server agrees. Clearing it now would snap the dropdown back
                // to the old value for the second or two before the refetch lands.
              }
            : null,
        style : OutlinedButton.styleFrom(
          minimumSize : const Size( 0, kMinInteractiveDimension ),
        ),
        child : const Text( 'Update' ),
      ),
    );
  }

  /// The owner control.
  ///
  /// 🔴 OWNER COMMITS ON CHANGE; PRIORITY DOES NOT. That asymmetry is the web's, carried
  /// rather than tidied (`taskRowController.ts:218-222` — *"The owner select is NOT
  /// staged: it has no Update button on either client's row, and commits on change as it
  /// always has."*). Normalising the two would make this client disagree with every
  /// other one about what a control does.
  ///
  /// ⚠️ THE CURRENT OWNER IS ALWAYS AN ENTRY, EVEN WHEN THEY ARE NOT A LIVE TARGET. A
  /// dropdown whose value is missing from its own items throws in Flutter, and the case
  /// is ordinary rather than exotic: a row owned by a persona who has since gone offline.
  /// So the select reflects reality first and offers the roster second.
  Widget _ownerDropdown( BuildContext context ) {
    final current = ( widget.ownerPersona ?? '' ).trim();
    final options = <String>[
      if ( current.isNotEmpty ) current,
      ...widget.ownerOptions.where( ( p ) => p != current ),
    ];

    return DropdownButton<String>(
      key   : const Key( TestKeys.taskFieldOwner ),
      value : current.isEmpty ? null : current,
      hint  : const Text( '(unassigned)' ),
      items : options
          .map( ( p ) => DropdownMenuItem<String>( value: p, child: Text( p ) ) )
          .toList( growable: false ),
      // A dropdown with nothing to move to is disabled rather than an empty menu that
      // opens onto nothing — which reads as broken rather than as "the phone cannot see
      // the fleet".
      onChanged : options.length < 2
          ? null
          : ( chosen ) {
              if ( chosen == null || chosen == current ) return;
              widget.onFieldChanged( ownerPersona: chosen );
            },
    );
  }
}
