import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../core/testing/test_keys.dart';
import '../../notifications/presentation/persona_badge.dart';
import '../data/broadcast_models.dart';
import '../domain/broadcast_bloc.dart';

/// Say something to the whole fleet at once.
///
/// Compose row, one line: `[🎤] [textarea] [Send]`, with a "Sending to:" count and a ↻
/// above it, and under that a row of MENTION CHIPS: `@all` plus one per live seat.
///
/// 🔴 A CHIP ADDRESSES NOBODY — IT TYPES. A broadcast always goes to EVERY live seat;
/// each seat reads the `@Persona` mentions in the body to decide what applies to it
/// (Rick, 2026-09-23: *"it carpet bombs everybody … it uses the at symbol so that all
/// recipients know whether it pertains to them"*). So tapping a chip inserts `@Name ` at
/// the caret, exactly as the web card does (`BroadcastCardRenderer.ts`
/// `injectMentionAtCursor`), and no per-recipient field is ever sent — the server's
/// request body has none, and would silently drop one.
///
/// 🔴 THE MIC IS THE POINT, AND IT HAS A RULING BEHIND IT. From `notifications.html`,
/// verbatim: *"added 2026-05-13 because Lupin is a voice-first app — typing into the
/// textarea was a regression from the established STT-button pattern used everywhere
/// else."* That argument is strictly stronger on a phone.
class BroadcastPane extends StatefulWidget {
  const BroadcastPane( { super.key } );

  @override
  State<BroadcastPane> createState() => _BroadcastPaneState();
}

class _BroadcastPaneState extends State<BroadcastPane> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController( text: context.read<BroadcastBloc>().state.body );
    // Only the roster is requested here. The history follows it from inside the bloc —
    // see `_onRoster`, which explains both why they are sequenced and what happens when
    // they are not.
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
      // The mic writes into the same box the operator types in, so the controller has to
      // follow the bloc when — and only when — the bloc is the one that changed it.
      // Assigning unconditionally would fight the keyboard and reset the caret on every
      // keystroke.
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
          ],
        );
      },
    );
  }

  /// "Sending to: N sessions  ↻" — a count and a refresh. Everyone receives it.
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

  /// `@all` plus one chip per live seat. Tapping one TYPES its mention — see the class
  /// note: the broadcast still goes to everyone.
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
            // The seat's own colour as the chip's outline, as on the web card; `@all`
            // and a seat with no (or a malformed) colour keep the theme's outline.
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

  /// Insert `@<name> ` at the caret (or over the selection), then hand the new text to
  /// the bloc. The controller changes FIRST, so the listener's `text != state.body`
  /// check finds them equal and leaves the caret where this put it.
  void _insertMention( BuildContext context, String name ) {
    final value  = _controller.value;
    final text   = value.text;
    final sel    = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed( offset: text.length );
    // One improvement on the web: a mention tapped straight after a word gets a space
    // first, or "standup" + "@Tiffany" would run together as "standup@Tiffany".
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
              // 🔴 THE PLACEHOLDER IS LOAD-BEARING DOCUMENTATION. It is the ONLY place a
              // user learns the @PersonaName: convention exists. Shortening it to
              // "Message" would delete the feature's discoverability.
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

  /// 🔴 A VISIBLE REASON, NOT A TOOLTIP.
  ///
  /// The web communicates this through `btn.title`. A phone has no hover, so a stale
  /// `active-sessions` fetch on flaky LTE would leave Send permanently dead with no
  /// reachable explanation — the operator holding a typed message and a grey button.
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

  /// The compose preview renders markdown. The ack summary does NOT — see [_tally].
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

  /// The ack tally.
  ///
  /// 🔴 THE ASYMMETRY WITH [_preview] IS A SAFETY PROPERTY, NOT AN INCONSISTENCY. The
  /// compose preview is the operator's OWN text and renders markdown. Each ack's
  /// `body_summary` is ANOTHER SESSION'S text and is rendered as a plain `Text` — the web
  /// sets it via `textContent`, never `innerHTML`, for exactly this reason. Letting both
  /// become a markdown widget would look tidier and would be the bug.
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
          // Plain Text. Not MarkdownBody. See the note above.
          subtitle : ack.bodySummary.isEmpty ? null : Text( ack.bodySummary ),
        ),
    ];
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

  /// ✅ THE CONFIRM MODAL IS CARRIED FROM THE WEB, DELIBERATELY.
  ///
  /// `broadcast-panel.js` ships one and this pane keeps it. That is NOT in tension with
  /// the batch-confirm ruling on the Holding Area: there the phone matches the web by
  /// having NO confirm, and here it matches the web by HAVING one. The rule is "match the
  /// web surface by surface", not "the phone never confirms" — and a broadcast interrupts
  /// every live seat at once, which is the widest blast radius in the app.
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
            // The operator's own text, so markdown — same reasoning as the preview.
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
