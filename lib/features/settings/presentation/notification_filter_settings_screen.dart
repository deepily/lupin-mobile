import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../../../services/notification_filter/notification_stop_list.dart';

/// The notification stop-list editor (plan 2026.08.21 §3). Each row is a
/// message PREFIX; checked = hidden from every list AND muted from TTS
/// (Rick 2026-08-21: one checkbox does both). Swipe to delete, "+" to add,
/// overflow menu to reset to the seeded Claude Code tool-chatter patterns.
class NotificationFilterSettingsScreen extends StatefulWidget {
  final NotificationStopList stopList;
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
                        child: CheckboxListTile(
                          key       : Key( '${TestKeys.settingsStopListTogglePrefix}${p.pattern}' ),
                          dense     : true,
                          title     : Text( p.pattern, style: const TextStyle( fontFamily: 'monospace' ) ),
                          subtitle  : Text( p.enabled ? 'hidden + muted' : 'shown + spoken' ),
                          value     : p.enabled,
                          onChanged : ( v ) => widget.stopList.setEnabled( i, v ?? false ),
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
