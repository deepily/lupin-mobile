import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../../../services/tts/tts_orchestrator.dart';

/// Bottom sheet over the focus screen that lists the queued speech.
///
/// The in-flight utterance comes first with a Skip button. The pending ones follow in play
/// order, each with a delete button. Clear queue drops the pending items only, and Stop all
/// cuts the current one too. The list follows [TtsOrchestrator.queueStream] live.
/// Nothing here is a mute: what the user deletes is gone, and what is left still plays.
class TtsQueueSheet extends StatelessWidget {
  /// The orchestrator whose queue is shown and edited.
  final TtsOrchestrator tts;

  /// Creates the sheet over [tts].
  const TtsQueueSheet( { super.key, required this.tts } );

  /// Opens the sheet as a modal bottom sheet over [context].
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
                _LastOutcomeLine( tts: tts ),
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

/// One plain line saying what became of the last message, or nothing before the first one.
///
/// A problem reads in the error colour so it is seen first; a normal send reads quietly.
class _LastOutcomeLine extends StatelessWidget {
  final TtsOrchestrator tts;
  const _LastOutcomeLine( { required this.tts } );

  @override
  Widget build( BuildContext context ) {
    final theme = Theme.of( context );
    return StreamBuilder<TtsOutcome>(
      stream      : tts.outcomeStream,
      initialData : tts.lastOutcome,
      builder: ( context, snap ) {
        final o = snap.data;
        if ( o == null ) return const SizedBox.shrink();
        final color = o.problem ? theme.colorScheme.error : theme.colorScheme.outline;
        return Padding(
          key     : const Key( TestKeys.ttsQueueLastOutcome ),
          padding : const EdgeInsets.fromLTRB( 16, 0, 16, 8 ),
          child   : Text( o.line, style: theme.textTheme.bodyMedium?.copyWith( color: color ) ),
        );
      },
    );
  }
}
