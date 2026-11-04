import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../../../services/notification_filter/notification_stop_list.dart';

/// The notification stop-list editor.
///
/// Each row is a message prefix. A checked row is hidden from every list and muted from
/// speech, with one checkbox doing both. The plus button adds a pattern, and the overflow
/// menu resets to the seeded Claude Code tool-chatter patterns.
/// A row has three gestures:
///  * the trash button deletes, with an Undo snackbar that puts the row back at its own
///    index with its own checked state;
///  * tapping the pattern text opens it for editing in place;
///  * swiping the row deletes it.
///
/// The checkbox is its own `Checkbox`, not a `CheckboxListTile`, and it is the only thing
/// that toggles. A list tile toggles on a tap anywhere in the row, which is the gesture
/// the text needs for editing.
/// Design: src/docs/decisions/README.md (R-SET-stoplist-one-checkbox)
class NotificationFilterSettingsScreen extends StatefulWidget {
  /// The store of patterns this screen edits.
  final NotificationStopList stopList;

  /// Creates the editor over [stopList].
  const NotificationFilterSettingsScreen( { super.key, required this.stopList } );

  @override
  State<NotificationFilterSettingsScreen> createState() =>
      _NotificationFilterSettingsScreenState();
}

class _NotificationFilterSettingsScreenState extends State<NotificationFilterSettingsScreen> {
  final _addCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.stopList.addListener( _rebuild );
  }

  @override
  void dispose() {
    widget.stopList.removeListener( _rebuild );
    _addCtrl.dispose();
    super.dispose();
  }

  void _rebuild() {
    if ( mounted ) setState( () {} );
  }

  Future<void> _add() async {
    final ok = await widget.stopList.add( _addCtrl.text );
    if ( ok ) _addCtrl.clear();
    if ( !ok && mounted ) {
      ScaffoldMessenger.of( context ).showSnackBar(
        const SnackBar( content: Text( 'Empty or duplicate pattern' ) ) );
    }
  }

  /// Deletes row [i] and offers the row back.
  ///
  /// The snackbar restores both the index and the checked state. A mis-tap has to be
  /// cheap to reverse, and an undo that appended an enabled copy would not be the row lost.
  Future<void> _delete( int i, StopPattern p ) async {
    await widget.stopList.removeAt( i );
    if ( !mounted ) return;
    ScaffoldMessenger.of( context )
      ..hideCurrentSnackBar()
      ..showSnackBar( SnackBar(
        content : Text( 'Deleted "${p.pattern}"' ),
        action  : SnackBarAction(
          label     : 'Undo',
          onPressed : () => widget.stopList.insertAt( i, p ),
        ),
      ) );
  }

  /// Edits the pattern at [i] in place.
  ///
  /// The store refuses a blank edit or one that collides with another row, and this
  /// reports it. The list is then left as it was, keeping the row's checked state and position.
  Future<void> _edit( int i, StopPattern p ) async {
    final text = await showDialog<String>(
      context : context,
      builder : ( _ ) => _EditPatternDialog( initial: p.pattern ),
    );
    if ( text == null ) return;   // Cancel, or dismissed — nothing to do
    final ok = await widget.stopList.editAt( i, text );
    if ( !ok && mounted ) {
      ScaffoldMessenger.of( context ).showSnackBar(
        const SnackBar( content: Text( 'Empty or duplicate pattern' ) ) );
    }
  }

  @override
  Widget build( BuildContext context ) {
    final patterns = widget.stopList.patterns;
    return Scaffold(
      appBar: AppBar(
        title   : const Text( 'Notification stop-list' ),
        actions : [
          PopupMenuButton<String>(
            key        : const Key( TestKeys.settingsStopListMenu ),
            onSelected : ( v ) { if ( v == 'reset' ) widget.stopList.resetToDefaults(); },
            itemBuilder: ( _ ) => const [
              PopupMenuItem( key: Key( TestKeys.settingsStopListReset ), value: 'reset',
                             child: Text( 'Reset to defaults' ) ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          SwitchListTile(
            key       : const Key( TestKeys.settingsCollapseGroups ),
            dense     : true,
            title     : const Text( 'Collapse tool-call bursts' ),
            subtitle  : const Text( 'One expandable row per progress group, like the web client.' ),
            value     : widget.stopList.collapseGroups,
            onChanged : ( v ) => widget.stopList.setCollapseGroups( v ),
          ),
          const Divider( height: 1 ),
          Padding(
            padding: const EdgeInsets.fromLTRB( 16, 12, 16, 4 ),
            child: Text(
              'Checked patterns are hidden from every message list AND never spoken. '
              'A pattern matches when a message starts with it (case-insensitive).',
              style: Theme.of( context ).textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB( 16, 4, 8, 4 ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key        : const Key( TestKeys.settingsStopListAddField ),
                    controller : _addCtrl,
                    decoration : const InputDecoration(
                      labelText : 'Add a prefix, e.g. "Done: WebFetch"',
                      isDense   : true,
                      border    : OutlineInputBorder(),
                    ),
                    onSubmitted: ( _ ) => _add(),
                  ),
                ),
                IconButton(
                  key       : const Key( TestKeys.settingsStopListAddButton ),
                  tooltip   : 'Add',
                  icon      : const Icon( Icons.add ),
                  onPressed : _add,
                ),
              ],
            ),
          ),
          const Divider( height: 1 ),
          Expanded(
            child: patterns.isEmpty
                ? const Center( child: Text( 'No patterns — everything is shown and spoken.' ) )
                : ListView.builder(
                    itemCount   : patterns.length,
                    itemBuilder : ( context, i ) {
                      final p = patterns[ i ];
                      return Dismissible(
                        key        : Key( '${TestKeys.settingsStopListRowPrefix}${p.pattern}' ),
                        direction  : DismissDirection.endToStart,
                        background : Container(
                          color     : Theme.of( context ).colorScheme.errorContainer,
                          alignment : Alignment.centerRight,
                          padding   : const EdgeInsets.only( right: 16 ),
                          child     : const Icon( Icons.delete_outline ),
                        ),
                        onDismissed: ( _ ) => widget.stopList.removeAt( i ),
                        child: ListTile(
                          dense    : true,
                          leading  : Checkbox(
                            key       : Key( '${TestKeys.settingsStopListTogglePrefix}${p.pattern}' ),
                            value     : p.enabled,
                            onChanged : ( v ) => widget.stopList.setEnabled( i, v ?? false ),
                          ),
                          title    : Text( p.pattern, style: const TextStyle( fontFamily: 'monospace' ) ),
                          subtitle : Text( p.enabled ? 'hidden + muted' : 'shown + spoken' ),
                          // Rick's words govern: "tapping a pattern's text opens it
                          // for editing". The box above is what toggles.
                          onTap    : () => _edit( i, p ),
                          trailing : IconButton(
                            key       : Key( '${TestKeys.settingsStopListDeletePrefix}${p.pattern}' ),
                            tooltip   : 'Delete',
                            icon      : const Icon( Icons.delete_outline ),
                            onPressed : () => _delete( i, p ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// The edit-in-place dialog, a widget that owns its own text controller.
///
/// The dialog's exit animation rebuilds its `TextField` after `pop`. Disposing a
/// caller-owned controller at the await's return point would use it after disposal, so
/// the controller's life is tied to the dialog's own.
class _EditPatternDialog extends StatefulWidget {
  final String initial;
  const _EditPatternDialog( { required this.initial } );

  @override
  State<_EditPatternDialog> createState() => _EditPatternDialogState();
}

class _EditPatternDialogState extends State<_EditPatternDialog> {
  late final TextEditingController _ctrl = TextEditingController( text: widget.initial );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build( BuildContext context ) {
    return AlertDialog(
      title   : const Text( 'Edit pattern' ),
      content : TextField(
        key         : const Key( TestKeys.settingsStopListEditField ),
        controller  : _ctrl,
        autofocus   : true,
        decoration  : const InputDecoration( border: OutlineInputBorder(), isDense: true ),
        onSubmitted : ( v ) => Navigator.of( context ).pop( v ),
      ),
      actions : [
        TextButton(
          key       : const Key( TestKeys.settingsStopListEditCancel ),
          onPressed : () => Navigator.of( context ).pop(),
          child     : const Text( 'Cancel' ),
        ),
        TextButton(
          key       : const Key( TestKeys.settingsStopListEditSave ),
          onPressed : () => Navigator.of( context ).pop( _ctrl.text ),
          child     : const Text( 'Save' ),
        ),
      ],
    );
  }
}
