import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../core/testing/test_keys.dart';
import '../../notifications/presentation/persona_badge.dart';
import '../data/broadcast_models.dart';
import '../domain/broadcast_bloc.dart';

/// Say something to the whole fleet at once.
///
/// A chip addresses nobody: it types an `@Persona` mention at the caret, as on the web. A
/// broadcast goes to every live seat, and each seat reads the mentions to decide what
/// applies to it. The mic is there because Lupin is voice-first.
/// Design: src/docs/decisions/README.md (R-BC-chips-type)
class BroadcastPane extends StatefulWidget {
  /// Creates the pane; it reads its [BroadcastBloc] from the route.
  const BroadcastPane( { super.key } );

  @override
  State<BroadcastPane> createState() => _BroadcastPaneState();
}

// The layout is a compose row `[mic] [textarea] [Send]`, a "Sending to:" count with a
// refresh button above it, and a row of mention chips below: `@all` plus one per live seat.
// No per-recipient field is ever sent, because the server's request body has none and would
// silently drop one. Typing into a textarea alone would be a regression from the speech
// button pattern used elsewhere, hence the mic.
class _BroadcastPaneState extends State<BroadcastPane> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController( text: context.read<BroadcastBloc>().state.body );
    // Only the roster is requested here. The history follows it from inside the bloc; see
    // `_onRoster`, which explains why they are sequenced and what happens when they are not.
    context.read<BroadcastBloc>().add( const BroadcastRosterRequested() );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build( BuildContext context ) {
    return BlocConsumer<BroadcastBloc, BroadcastState>(
      // The mic writes into the same box the operator types in, so the controller follows
      // the bloc only when the bloc is the one that changed it. Assigning unconditionally
      // would fight the keyboard and reset the caret on every keystroke.
      listenWhen : ( prev, next ) => prev.body != next.body,
      listener   : ( context, state ) {
        if ( _controller.text != state.body ) {
          _controller.value = TextEditingValue(
            text      : state.body,
            selection : TextSelection.collapsed( offset: state.body.length ),
          );
        }
      },
      builder : ( context, state ) {
        return ListView(
          key      : const Key( TestKeys.broadcastView ),
          padding  : const EdgeInsets.all( 16 ),
          children : [
            _recipients( context, state ),
            _mentionChips( context, state ),
            const SizedBox( height: 8 ),
            _composeRow( context, state ),
            _disabledReason( context, state ),
            if ( state.micError != null ) _micError( context, state ),
            if ( state.sendError != null )
              _notice( context, state.sendError! ),
            if ( state.rateLimitedForSeconds != null )
              _notice( context, _rateLimitText( state.rateLimitedForSeconds! ) ),
            if ( state.hasBody ) ..._preview( context, state ),
            if ( state.aggregate != null ) ..._tally( context, state.aggregate! ),
            if ( state.historyLoaded ) ..._history( context, state ),
          ],
        );
      },
    );
  }

  // "Sending to: N sessions" with a refresh button; everyone receives the broadcast.
  Widget _recipients( BuildContext context, BroadcastState state ) {
    return Row(
      children : [
        Expanded(
          child : Text(
            key  : const Key( TestKeys.broadcastRecipientCount ),
            state.rosterLoading
                ? 'Sending to: …'
                : 'Sending to: ${state.roster.count} session'
                    '${state.roster.count == 1 ? '' : 's'}',
          ),
        ),
        IconButton(
          key       : const Key( TestKeys.broadcastRecipientRefresh ),
          icon      : const Text( '↻' ),
          tooltip   : 'Refresh the session list',
          onPressed : () =>
              context.read<BroadcastBloc>().add( const BroadcastRosterRequested() ),
        ),
      ],
    );
  }

  // `@all` plus one chip per live seat. Tapping one types its mention; the broadcast still
  // goes to everyone.
  Widget _mentionChips( BuildContext context, BroadcastState state ) {
    final names = <String>[ 'all', for ( final s in state.roster.sessions ) s.label ];
    return Wrap(
      key        : const Key( TestKeys.broadcastMentionChips ),
      spacing    : 6,
      runSpacing : 4,
      children   : [
        for ( var i = 0; i < names.length; i++ )
          ActionChip(
            key     : Key( '${TestKeys.broadcastMentionChipPrefix}${names[ i ]}' ),
            avatar  : Text( i == 0 ? '📣' : ( state.roster.sessions[ i - 1 ].personaIcon ?? '👤' ) ),
            label   : Text( names[ i ] ),
            // The seat's own colour as the chip's outline, as on the web card; `@all` and a
            // seat with no or a malformed colour keep the theme's outline.
            side    : _seatSide( i == 0 ? null : state.roster.sessions[ i - 1 ].personaColor ),
            tooltip : 'Insert @${names[ i ]} into the message',
            onPressed : () => _insertMention( context, names[ i ] ),
          ),
      ],
    );
  }

  BorderSide? _seatSide( String? hex ) {
    final color = PersonaBadge.colorOfHex( hex );
    return color == null ? null : BorderSide( color: color, width: 2 );
  }

  // Inserts `@<name> ` at the caret, or over the selection, then hands the new text to the
  // bloc. The controller changes first, so the listener's `text != state.body` check finds
  // them equal and leaves the caret where this put it.
  void _insertMention( BuildContext context, String name ) {
    final value  = _controller.value;
    final text   = value.text;
    final sel    = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed( offset: text.length );
    // A mention tapped straight after a word gets a space first, an improvement on the web,
    // or "standup" and "@Tiffany" would run together as "standup@Tiffany".
    final glued  = sel.start > 0 && text[ sel.start - 1 ].trim().isNotEmpty;
    final insert = '${glued ? ' ' : ''}@$name ';
    final next   = text.replaceRange( sel.start, sel.end, insert );

    _controller.value = TextEditingValue(
      text      : next,
      selection : TextSelection.collapsed( offset: sel.start + insert.length ),
    );
    context.read<BroadcastBloc>().add( BroadcastBodyChanged( next ) );
  }

  Widget _composeRow( BuildContext context, BroadcastState state ) {
    final bloc = context.read<BroadcastBloc>();

    return Row(
      crossAxisAlignment : CrossAxisAlignment.end,
      children : [
        IconButton(
          key       : const Key( TestKeys.broadcastMicButton ),
          icon      : Text( state.mic == MicState.listening ? '⏹' : '🎤' ),
          tooltip   : state.mic == MicState.listening ? 'Stop and transcribe' : 'Speak',
          onPressed : state.mic == MicState.transcribing
              ? null
              : () => bloc.add( const BroadcastMicToggled() ),
        ),
        Expanded(
          child : TextField(
            key        : const Key( TestKeys.broadcastBodyField ),
            controller : _controller,
            maxLines   : 4,
            minLines   : 2,
            onChanged  : ( text ) => bloc.add( BroadcastBodyChanged( text ) ),
            decoration : const InputDecoration(
              border : OutlineInputBorder(),
              // The placeholder is the only place a user learns the @PersonaName: convention
              // exists, so shortening it to "Message" would delete the feature's
              // discoverability.
              hintText : 'Use @PersonaName: lines for persona-specific directives. '
                         'Markdown supported.',
            ),
          ),
        ),
        const SizedBox( width: 8 ),
        FilledButton(
          key       : const Key( TestKeys.broadcastSendButton ),
          onPressed : state.canSend ? () => _confirmThenSend( context, state ) : null,
          child     : const Text( 'Send' ),
        ),
      ],
    );
  }

  // A visible reason, not a tooltip. The web communicates this through `btn.title`, and a
  // phone has no hover, so a stale `active-sessions` fetch on flaky LTE would leave Send
  // dead with no reachable explanation: the operator holding a typed message and a grey
  // button.
  Widget _disabledReason( BuildContext context, BroadcastState state ) {
    final reason = state.disabledReason;
    if ( reason == null ) return const SizedBox.shrink();

    return Padding(
      padding : const EdgeInsets.only( top: 6 ),
      child   : Semantics(
        liveRegion : true,
        child : Text(
          reason,
          key   : const Key( TestKeys.broadcastDisabledReason ),
          style : TextStyle( color: Theme.of( context ).colorScheme.error ),
        ),
      ),
    );
  }

  // The compose preview renders markdown; the ack summary does not, see `_tally`.
  List<Widget> _preview( BuildContext context, BroadcastState state ) {
    return [
      const SizedBox( height: 16 ),
      Text( 'Preview', style: Theme.of( context ).textTheme.labelMedium ),
      Container(
        key       : const Key( TestKeys.broadcastPreview ),
        width     : double.infinity,
        padding   : const EdgeInsets.all( 8 ),
        decoration : BoxDecoration(
          border : Border.all( color: Theme.of( context ).dividerColor ),
        ),
        child : MarkdownBody( data: state.body ),
      ),
    ];
  }

  // The ack tally. The asymmetry with `_preview` is a safety property: the compose preview
  // is the operator's own text and renders markdown, while each ack's `body_summary` is
  // another session's text and is a plain `Text`. The web sets it via `textContent`, never
  // `innerHTML`, for the same reason. Making both markdown would look tidier and be the bug.
  List<Widget> _tally( BuildContext context, AckAggregate agg ) {
    return [
      const SizedBox( height: 24 ),
      Semantics(
        liveRegion : true,
        child : Text(
          agg.summary,
          key   : const Key( TestKeys.broadcastAckSummary ),
          style : Theme.of( context ).textTheme.titleSmall,
        ),
      ),
      for ( final ack in agg.acks )
        ListTile(
          key      : Key( '${TestKeys.broadcastAckRowPrefix}${ack.sessionId}' ),
          dense    : true,
          leading  : Text( ack.personaIcon ?? '•' ),
          title    : Text( ack.label ),
          // Plain Text, not MarkdownBody; see the comment above.
          subtitle : ack.bodySummary.isEmpty ? null : Text( ack.bodySummary ),
        ),
    ];
  }

  // Recent broadcast activity. It has three answers, never two: switched off on the server,
  // quiet, and a list are different facts, and the first used to render as the second.
  // Entries are other sessions' words, so they are plain `Text`, the same rule as `_tally`.
  List<Widget> _history( BuildContext context, BroadcastState state ) {
    final muted = Theme.of( context ).colorScheme.outline;
    return [
      const SizedBox( height: 24 ),
      Text( 'Recent activity', style: Theme.of( context ).textTheme.labelMedium ),
      if ( state.historyDisabled )
        Padding(
          padding : const EdgeInsets.only( top: 6 ),
          child   : Text(
            'Broadcast history is switched off on the server',
            key   : const Key( TestKeys.broadcastHistoryDisabled ),
            style : TextStyle( color: muted, fontStyle: FontStyle.italic ),
          ),
        )
      else if ( state.history.isEmpty )
        Padding(
          padding : const EdgeInsets.only( top: 6 ),
          child   : Text(
            'No recent broadcasts',
            key   : const Key( TestKeys.broadcastHistoryEmpty ),
            style : TextStyle( color: muted ),
          ),
        )
      else
        for ( var i = 0; i < state.history.length; i++ )
          ListTile(
            key      : Key( '${TestKeys.broadcastHistoryRowPrefix}$i' ),
            dense    : true,
            leading  : Text( state.history[ i ][ 'persona_icon' ]?.toString() ?? '•' ),
            title    : Text( _historyTitle( state.history[ i ] ) ),
            // Plain Text, not MarkdownBody; see `_tally`.
            subtitle : Text(
              state.history[ i ][ 'body' ]?.toString() ?? '',
              maxLines : 3,
              overflow : TextOverflow.ellipsis,
            ),
          ),
    ];
  }

  // `persona · HH:MM`, in the phone's local time.
  String _historyTitle( Map<String, dynamic> entry ) {
    final who = entry[ 'persona_name' ]?.toString() ?? 'unknown';
    final ts  = DateTime.tryParse( entry[ 'ts' ]?.toString() ?? '' )?.toLocal();
    if ( ts == null ) return who;
    final hh  = ts.hour.toString().padLeft( 2, '0' );
    final mm  = ts.minute.toString().padLeft( 2, '0' );
    return '$who · $hh:$mm';
  }

  Widget _micError( BuildContext context, BroadcastState state ) {
    return Padding(
      padding : const EdgeInsets.only( top: 6 ),
      child   : Semantics(
        liveRegion : true,
        child      : Text(
          state.micError!,
          key   : const Key( TestKeys.broadcastMicError ),
          style : TextStyle( color: Theme.of( context ).colorScheme.error ),
        ),
      ),
    );
  }

  Widget _notice( BuildContext context, String text ) {
    return Container(
      key     : const Key( TestKeys.broadcastNotice ),
      margin  : const EdgeInsets.only( top: 12 ),
      padding : const EdgeInsets.all( 12 ),
      color   : Theme.of( context ).colorScheme.errorContainer,
      child   : Semantics( liveRegion: true, child: Text( text ) ),
    );
  }

  String _rateLimitText( int seconds ) => seconds > 0
      ? 'Too many broadcasts — try again in $seconds seconds.'
      : 'Too many broadcasts — try again shortly.';

  // The confirm modal is carried from the web, where `broadcast-panel.js` ships one. That
  // does not conflict with the Holding Area's batch confirm: the rule is "match the web
  // surface by surface", not "the phone never confirms", and a broadcast interrupts every
  // live seat at once, the widest blast radius in the app.
  // Design: src/docs/decisions/README.md (R-BC-confirm-kept)
  Future<void> _confirmThenSend( BuildContext context, BroadcastState state ) async {
    final bloc = context.read<BroadcastBloc>();

    final ok = await showDialog<bool>(
      context : context,
      builder : ( dialogContext ) => AlertDialog(
        key     : const Key( TestKeys.broadcastSendConfirm ),
        title   : Text( 'Send to ${state.roster.count} session'
                        '${state.roster.count == 1 ? '' : 's'}?' ),
        content : Column(
          mainAxisSize       : MainAxisSize.min,
          crossAxisAlignment : CrossAxisAlignment.start,
          children : [
            Wrap(
              spacing  : 6,
              children : [
                for ( final s in state.roster.sessions )
                  Chip( label: Text( '${s.personaIcon ?? ''} ${s.label}'.trim() ) ),
              ],
            ),
            const SizedBox( height: 12 ),
            // The operator's own text, so markdown, as in the preview.
            MarkdownBody( data: state.body ),
          ],
        ),
        actions : [
          TextButton(
            key       : const Key( TestKeys.broadcastSendConfirmNo ),
            onPressed : () => Navigator.of( dialogContext ).pop( false ),
            child     : const Text( 'Cancel' ),
          ),
          FilledButton(
            key       : const Key( TestKeys.broadcastSendConfirmOk ),
            onPressed : () => Navigator.of( dialogContext ).pop( true ),
            child     : const Text( 'Send' ),
          ),
        ],
      ),
    );

    if ( ok == true ) bloc.add( const BroadcastSendConfirmed() );
  }
}
