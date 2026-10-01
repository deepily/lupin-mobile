import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';

/// The two field-door controls: priority and owner.
///
/// Both go through `PATCH /api/tasks/{id}`, which addresses exactly two keys and not
/// `status`; a status change sent there is silently ignored. This widget reports a
/// priority and an owner, never a status, and
/// `TaskWriteRepository.patchFields` cannot send one. It takes no pane parameter: the
/// roster and the current values arrive as data, so both task panes may pass the same ones.
class TaskFieldControls extends StatefulWidget {
  /// The row's painted priority, or null when it carries none.
  final String? priority;

  /// The row's painted owner, or null when unassigned.
  final String? ownerPersona;

  /// The personas this row may be reassigned to; empty when the phone cannot see the fleet.
  ///
  /// See `activeReassignTargets`.
  final List<String> ownerOptions;

  /// Called when the operator commits a change; exactly one argument is non-null.
  final void Function( { String? priority, String? ownerPersona } ) onFieldChanged;

  /// Creates the controls for one row.
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

/// The priorities an operator may choose, in rank order.
const List<String> kEditablePriorities = <String>[ 'P0', 'P1', 'P2', 'P3', 'P4', 'P5' ];

class _TaskFieldControlsState extends State<TaskFieldControls> {
  // The priority the operator has chosen but not yet sent; null means same as painted.
  String? _stagedPriority;

  @override
  void didUpdateWidget( TaskFieldControls old ) {
    super.didUpdateWidget( old );
    // A poll that repaints the row must not strand a staged edit. When the painted
    // priority catches up with the staged one, because the operator's own Update landed or
    // someone made the same change, the staging is spent and Update goes disabled again.
    // The comparison is against the painted value, because the row survives a repaint and
    // in-widget memory of the old value does not.
    if ( old.priority != widget.priority && _stagedPriority == widget.priority ) {
      _stagedPriority = null;
    }
  }

  String? get _chosenPriority => _stagedPriority ?? widget.priority;

  // The Update button stays disabled until the chosen value differs from the painted one,
  // because a live button on an untouched row would assert nothing and still cost a round
  // trip. Design: src/docs/decisions/README.md (R-TF-update-gated)
  bool get _priorityMoved =>
      _stagedPriority != null && _stagedPriority != widget.priority;

  @override
  Widget build( BuildContext context ) {
    // A `Wrap`, not a `Row`: at 360 dp two dropdowns and a button do not share a line with
    // 16 dp gutters, and an overflow would clip the control instead of wrapping it.
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

  // The editable ranks, plus the row's own value when the store holds one this list does
  // not know. An unrecognised priority such as `P9` gets its own entry; showing it as `P0`
  // would mislead the operator, and Update would then change a value nobody chose.
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
                // The staging is not cleared here. The poll after the write repaints the
                // row and `didUpdateWidget` retires it once the server agrees. Clearing it
                // now would snap the dropdown back to the old value until the refetch lands.
              }
            : null,
        style : OutlinedButton.styleFrom(
          minimumSize : const Size( 0, kMinInteractiveDimension ),
        ),
        child : const Text( 'Update' ),
      ),
    );
  }

  // The owner control. Owner commits on change and priority does not; the web client has
  // the same asymmetry, and making them match would change what a control does here.
  // The current owner is always an entry, even when not a live target, because a Flutter
  // dropdown whose value is missing from its items throws, and a row owned by a persona
  // who has gone offline is ordinary.
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
      // With nothing to move to the dropdown is disabled; an empty menu would read as broken.
      onChanged : options.length < 2
          ? null
          : ( chosen ) {
              if ( chosen == null || chosen == current ) return;
              widget.onFieldChanged( ownerPersona: chosen );
            },
    );
  }
}
