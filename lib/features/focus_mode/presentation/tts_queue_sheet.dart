import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../../../services/tts/tts_orchestrator.dart';

/// TTS queue viewer (Rick 2026-08-21: "a pop-up queued TTS message viewer
/// that lets me delete / skip messages that are noisy" — web
/// `#tts-queue-section` parity). Bottom sheet over the focus screen:
/// the in-flight utterance first with **Skip**, then the pending ones in
/// play order with a per-row delete, plus **Clear queue** (pending only)
/// and **Stop all** (cuts the current one too). Live off
/// [TtsOrchestrator.queueStream]; nothing here is a mute — what you delete
/// is gone, what you leave still plays.
class TtsQueueSheet extends StatelessWidget {
  final TtsOrchestrator tts;
  const TtsQueueSheet( { super.key, required this.tts } );

  static Future<void> show( BuildContext context, TtsOrchestrator tts ) =>
      showModalBottomSheet<void>(
        context     : context,
        showDragHandle : true,
        isScrollControlled : true,
        builder     : ( _ ) => TtsQueueSheet( tts: tts ),
      );

  @override
  Widget build( BuildContext context ) {
    final theme = Theme.of( context );
    return SafeArea(
      child: StreamBuilder<List<TtsQueueItem>>(
        stream      : tts.queueStream,
        initialData : tts.queueSnapshot,
        builder: ( context, snap ) {
          final items   = snap.data ?? const <TtsQueueItem>[];
          final current = items.where( ( i ) => i.isCurrent ).toList();
          final pending = items.where( ( i ) => !i.isCurrent ).toList();
          return ConstrainedBox(
            key         : const Key( TestKeys.ttsQueueSheet ),
            constraints : BoxConstraints( maxHeight: MediaQuery.of( context ).size.height * 0.7 ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB( 16, 0, 8, 4 ),
                  child: Row(
                    children: [
                      const Icon( Icons.volume_up, size: 18 ),
                      const SizedBox( width: 8 ),
                      Expanded( child: Text( 'Speech queue · ${current.length} playing · ${pending.length} queued',
                          style: theme.textTheme.titleSmall ) ),
                      TextButton.icon(
                        key       : const Key( TestKeys.ttsQueueClear ),
                        onPressed : pending.isEmpty ? null : tts.clearQueued,
                        icon      : const Icon( Icons.playlist_remove, size: 18 ),
                        label     : const Text( 'Clear queue' ),
                      ),
                      IconButton(
                        key       : const Key( TestKeys.ttsQueueStopAll ),
                        tooltip   : 'Stop all (current + queue)',
                        onPressed : items.isEmpty ? null : tts.stopAll,
                        icon      : const Icon( Icons.stop_circle_outlined ),
                      ),
                    ],
                  ),
                ),
                if ( items.isEmpty )
                  Padding(
                    key     : const Key( TestKeys.ttsQueueEmpty ),
                    padding : const EdgeInsets.all( 24 ),
                    child   : Text( 'Nothing queued — it is quiet.',
                        textAlign: TextAlign.center, style: theme.textTheme.bodyMedium ),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for ( final c in current ) _QueueRow( item: c, onAction: tts.skipCurrent, actionIcon: Icons.skip_next, actionKey: const Key( TestKeys.ttsQueueSkip ), actionTooltip: 'Skip' ),
                        if ( current.isNotEmpty && pending.isNotEmpty ) const Divider( height: 1 ),
                        for ( final p in pending )
                          _QueueRow(
                            item          : p,
                            onAction      : () => tts.removeQueued( p.id ),
                            actionIcon    : Icons.delete_outline,
                            actionKey     : Key( '${TestKeys.ttsQueueDeletePrefix}${p.id}' ),
                            actionTooltip : 'Delete',
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  final TtsQueueItem item;
  final VoidCallback onAction;
  final IconData     actionIcon;
  final Key          actionKey;
  final String       actionTooltip;
  const _QueueRow( {
    required this.item,
    required this.onAction,
    required this.actionIcon,
    required this.actionKey,
    required this.actionTooltip,
  } );

  @override
  Widget build( BuildContext context ) {
    final theme  = Theme.of( context );
    final icon   = item.sender.icon;
    final glyph  = ( icon != null && icon.isNotEmpty ) ? icon : ( item.sender.isPersona ? '🗣' : '⚙' );
    final label  = item.sender.label;
    return ListTile(
      key     : Key( '${TestKeys.ttsQueueRowPrefix}${item.id}' ),
      dense   : true,
      leading : Text( glyph, style: const TextStyle( fontSize: 20 ) ),
      title   : Text( item.text, maxLines: 2, overflow: TextOverflow.ellipsis ),
      subtitle: Text( item.isCurrent ? '$label · playing' : '$label · ${item.priority}',
          style: theme.textTheme.labelSmall ),
      tileColor: item.isCurrent ? theme.colorScheme.primaryContainer.withValues( alpha: 0.35 ) : null,
      trailing: IconButton(
        key       : actionKey,
        tooltip   : actionTooltip,
        icon      : Icon( actionIcon ),
        onPressed : onAction,
      ),
    );
  }
}
