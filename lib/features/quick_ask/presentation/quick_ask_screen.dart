import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/service_locator.dart';
import '../../../core/testing/test_keys.dart';
import '../../../services/tts/tts_orchestrator.dart';
import '../../../shared/widgets/prompt_bodies.dart';
import '../../../shared/widgets/tts_pause_control.dart';
import '../../queue/domain/job_lifecycle.dart';
import '../data/quick_ask_models.dart';
import '../domain/quick_ask_bloc.dart';
import '../domain/quick_ask_event.dart';
import '../domain/quick_ask_state.dart';

/// Quick Ask: tap, speak a question, tap again to stop, send it, and read the answer.
///
/// The button is a tap toggle, not a hold.
/// Stopping only parks the transcript, and the small send button under the microphone
/// is the only thing that puts it on the wire.
///
/// The record button is a fixed header, not the first list item, so the list below stays a plain scrollback.
/// The scrollback sits below it with the newest pair on top.
class QuickAskScreen extends StatelessWidget {
  /// Creates the screen.
  const QuickAskScreen( { super.key } );

  @override
  Widget build( BuildContext context ) {
    // Mount the shared pause control instead of re-implementing it.
    // A third stream builder over `pausedStream` in this file would be the defect that sharing prevents.
    final tts = ServiceLocator.get<TtsOrchestrator>();

    return Scaffold(
      appBar : AppBar(
        title   : const Text( 'Quick Ask' ),
        actions : [ TtsPauseToggle(
          tts       : tts,
          toggleKey : const Key( TestKeys.quickAskPauseToggle ),
        ) ],
      ),
      body   : BlocBuilder<QuickAskBloc, QuickAskState>(
        builder: ( context, state ) {
          return Column(
            children: [
              // A user who paused in focus mode arrives here to a stated reason, not a bare icon.
              // The banner renders nothing when speech is not held.
              TtsPausedBanner(
                tts       : tts,
                bannerKey : const Key( TestKeys.quickAskPausedBanner ),
                reason    : 'Tap replay on an answer to resume.',
              ),
              _RecordHeader( state: state ),
              // Everything below the fixed header scrolls together.
              // The interlock surfaces were once fixed children of this column.
              // On a 320x568 phone the header plus a confirm prompt was already 10 px taller than the body,
              // and a prompt plus an error was 114 px taller.
              // A `Column` cannot shrink a non-flexible child, so it overflowed instead of scrolling.
              // They are now the leading items of the scrollback list, the only arrangement that cannot overflow
              // whatever combination of them is live.
              Expanded( child: _Scrollback( state: state, tts: tts ) ),
            ],
          );
        },
      ),
    );
  }
}

class _RecordHeader extends StatelessWidget {
  final QuickAskState state;
  const _RecordHeader( { required this.state } );

  @override
  Widget build( BuildContext context ) {
    final bloc      = context.read<QuickAskBloc>();
    final recording = state.phase == QuickAskPhase.recording;
    // `canRecord` already goes false while a draft is held,
    // so the microphone cannot be tapped out from under a question that was spoken but not sent.
    final enabled   = state.canRecord;
    final hasDraft  = state.hasDraft;
    // While a confirm prompt or an interview turn is live and the microphone is inert,
    // a 128 px circle is 128 px of screen spent on a control that cannot be pressed,
    // taken from the question that holds the ask open.
    // The circle shrinks in exactly those states.
    // On a 320x568 phone that is the difference between the whole prompt being on screen
    // and its answer buttons sitting under the fold.
    //
    // `!enabled` is required, not belt and braces.
    // `canRecord` has an escape hatch for `phase == recording`,
    // and the bloc's notification handler sets `pendingPrompt` with no phase guard.
    // So a `response_requested` can arrive mid-capture, on a screen whose microphone is the live
    // "tap to stop" control.
    // Shrinking that under a recording user's thumb is a moving target for a gesture already in progress.
    // It stays 128 until the capture ends.
    final blocked   = ( state.pendingPrompt != null || state.interview != null ) && !enabled;
    final micSize   = blocked ?  84.0 : 128.0;
    final micIcon   = blocked ?  40.0 :  60.0;
    final stackTall = blocked ? 124.0 : 168.0;
    final padTall   = blocked ?  10.0 :  16.0;

    return Material(
      elevation : 2,
      child     : Padding(
        padding : EdgeInsets.symmetric( vertical: padTall, horizontal: 12 ),
        child   : Column(
          children: [
            // The send-mode control lives here, above the record button.
            // The widget is shaped like the SegmentedButton in `_ServerContextToggleState.build`.
            // The mode comes from state, not widget-local state, and a pick goes back through the bloc.
            //
            // It is compact, and hidden while a confirm prompt or an interview is live.
            // The header is fixed, so every pixel it gains comes out of the column below,
            // and those surfaces must stay on screen.
            // Nothing new can be recorded until they are answered, so there is no send mode left to pick.
            // The one gap is a capture already running when the prompt arrived,
            // which keeps the mode it started under.
            // This control is render-only and the release path reads `QuickAskPreferences`,
            // so hiding it cannot change that capture's outcome.
            if ( state.pendingPrompt == null && state.interview == null ) Padding(
              padding : const EdgeInsets.only( bottom: 4 ),
              child   : SegmentedButton<bool>(
                key      : const Key( TestKeys.quickAskSendModeToggle ),
                showSelectedIcon : false,
                style    : const ButtonStyle(
                  visualDensity   : VisualDensity.compact,
                  tapTargetSize   : MaterialTapTargetSize.shrinkWrap,
                ),
                segments : const [
                  ButtonSegment<bool>( value: false, label: Text( 'Review first' ) ),
                  ButtonSegment<bool>( value: true,  label: Text( 'Send immediately' ) ),
                ],
                selected           : { state.sendImmediately },
                onSelectionChanged : ( s ) => bloc.add( QuickAskSendModeChanged( s.first ) ),
              ),
            ),
            SizedBox(
              // The width is unchanged so the clear and send buttons keep their corners clear of the circle
              // even at the smaller microphone size.
              width  : 232,
              height : stackTall,
              child  : Stack(
                alignment : Alignment.topCenter,
                children  : [
                  GestureDetector(
                    key     : const Key( TestKeys.quickAskRecordButton ),
                    // One tap starts and the next stops.
                    // It is `onTap` and not a long press, so no finger has to stay down.
                    onTap   : enabled
                        ? () => bloc.add( recording
                            ? const QuickAskRecordReleased()
                            : const QuickAskRecordPressed() )
                        : null,
                    child   : _PulsingMic(
                      active   : recording,
                      enabled  : enabled,
                      size     : micSize,
                      iconSize : micIcon,
                    ),
                  ),
                  Positioned(
                    left    : 0,
                    bottom  : 0,
                    child   : _DraftAction(
                      actionKey : const Key( TestKeys.quickAskClearButton ),
                      icon      : Icons.close,
                      tooltip   : 'Clear',
                      colour    : Theme.of( context ).colorScheme.error,
                      onPressed : hasDraft
                          ? () => bloc.add( const QuickAskDraftCleared() )
                          : null,
                    ),
                  ),
                  Positioned(
                    right   : 0,
                    bottom  : 0,
                    child   : _DraftAction(
                      actionKey : const Key( TestKeys.quickAskSendButton ),
                      icon      : Icons.play_arrow,
                      tooltip   : 'Send',
                      colour    : Theme.of( context ).colorScheme.primary,
                      onPressed : hasDraft
                          ? () => bloc.add( const QuickAskDraftSent() )
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox( height: 8 ),
            Text( _headline( state ), style: Theme.of( context ).textTheme.bodyMedium ),
            // What the send button will actually send.
            // Without it, "ready to send" asks the user to trust a transcript they have not seen.
            if ( hasDraft )
              Padding(
                padding : const EdgeInsets.only( top: 4, left: 16, right: 16 ),
                child   : Text(
                  key       : const Key( TestKeys.quickAskDraftText ),
                  '“${state.draftTranscript}”',
                  textAlign : TextAlign.center,
                  style     : Theme.of( context ).textTheme.bodySmall,
                ),
              ),
            if ( state.blockedMessage != null )
              Padding(
                padding : const EdgeInsets.only( top: 4 ),
                child   : Text(
                  key   : const Key( TestKeys.quickAskBlockedReason ),
                  state.blockedMessage!,
                  style : TextStyle( color: Theme.of( context ).colorScheme.error, fontSize: 12 ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _headline( QuickAskState s ) {
    switch ( s.phase ) {
      case QuickAskPhase.recording:     return 'Listening… tap to stop';
      case QuickAskPhase.transcribing:  return 'Transcribing…';
      case QuickAskPhase.review:        return 'Ready to send';
      case QuickAskPhase.submitting:    return 'Sending…';
      case QuickAskPhase.waiting:       return 'Working on it…';
      case QuickAskPhase.idle:          return 'Tap to ask';
    }
  }
}

/// A small control beside the microphone: clear on the lower left, send on the lower right.
///
/// They are much smaller than the microphone: the microphone is aimed at, these are confirmed with.
class _DraftAction extends StatelessWidget {
  final Key           actionKey;
  final IconData      icon;
  final String        tooltip;
  final Color         colour;
  final VoidCallback? onPressed;

  const _DraftAction( {
    required this.actionKey,
    required this.icon,
    required this.tooltip,
    required this.colour,
    required this.onPressed,
  } );

  @override
  Widget build( BuildContext context ) {
    final live = onPressed != null;
    return IconButton(
      key       : actionKey,
      icon      : Icon( icon, size: 26 ),
      tooltip   : tooltip,
      onPressed : onPressed,
      style     : IconButton.styleFrom(
        backgroundColor : live
            ? colour.withValues( alpha: 0.15 )
            : Theme.of( context ).colorScheme.onSurface.withValues( alpha: 0.06 ),
        foregroundColor : live
            ? colour
            : Theme.of( context ).colorScheme.onSurface.withValues( alpha: 0.25 ),
        shape           : const CircleBorder(),
        padding         : const EdgeInsets.all( 12 ),
      ),
    );
  }
}

class _PulsingMic extends StatefulWidget {
  final bool   active;
  final bool   enabled;
  final double size;
  final double iconSize;
  const _PulsingMic( {
    required this.active,
    required this.enabled,
    required this.size,
    required this.iconSize,
  } );

  @override
  State<_PulsingMic> createState() => _PulsingMicState();
}

class _PulsingMicState extends State<_PulsingMic> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync    : this,
    duration : const Duration( milliseconds: 900 ),
  );

  @override
  void didUpdateWidget( covariant _PulsingMic old ) {
    super.didUpdateWidget( old );
    if ( widget.active && !_ctrl.isAnimating ) {
      _ctrl.repeat( reverse: true );
    } else if ( !widget.active && _ctrl.isAnimating ) {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build( BuildContext context ) {
    final scheme = Theme.of( context ).colorScheme;
    final colour = !widget.enabled
        ? scheme.onSurface.withValues( alpha: 0.25 )
        : ( widget.active ? scheme.error : scheme.primary );

    return AnimatedBuilder(
      animation : _ctrl,
      builder   : ( context, _ ) {
        final scale = widget.active ? 1.0 + ( _ctrl.value * 0.12 ) : 1.0;
        return Transform.scale(
          scale : scale,
          child : Container(
            width       : widget.size,
            height      : widget.size,
            decoration  : BoxDecoration( shape: BoxShape.circle, color: colour ),
            child       : Icon( Icons.mic, size: widget.iconSize, color: scheme.onPrimary ),
          ),
        );
      },
    );
  }
}

/// A `response_requested` notification from the WebSocket, shown while the ask is in flight.
///
/// The near-match confirm blocks the ask it belongs to, for about 210 s worst case,
/// and defaults to "no" when nobody replies.
/// Recording the id without showing the question disabled the record button,
/// so the confirm always expired to "no" and the user saw a mysterious pause.
/// The bodies are the shared ones, which do not know which endpoint they post to.
/// This host picks the endpoint.
class _PendingPrompt extends StatelessWidget {
  final QuickAskPrompt prompt;
  const _PendingPrompt( { required this.prompt } );

  @override
  Widget build( BuildContext context ) {
    final scheme = Theme.of( context ).colorScheme;
    void respond( String v ) =>
        context.read<QuickAskBloc>().add( QuickAskPromptAnswered( v ) );

    return Container(
      key     : const Key( TestKeys.quickAskPrompt ),
      width   : double.infinity,
      color   : scheme.tertiaryContainer,
      padding : const EdgeInsets.all( 12 ),
      child   : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon( Icons.live_help_outlined, size: 18 ),
              const SizedBox( width: 8 ),
              Expanded(
                child: Text(
                  key   : const Key( TestKeys.quickAskPromptQuestion ),
                  prompt.question,
                  style : const TextStyle( fontWeight: FontWeight.w600 ),
                ),
              ),
              IconButton(
                key       : const Key( TestKeys.quickAskPromptDismiss ),
                icon      : const Icon( Icons.close ),
                // Not a local hide: dismissing posts the default,
                // so the blocked ask stops waiting instead of running out its retry ladder.
                tooltip   : 'Dismiss (answers "${prompt.defaultAnswer}")',
                onPressed : () => context.read<QuickAskBloc>()
                    .add( const QuickAskPromptDismissed() ),
              ),
            ],
          ),
          // The near-match confirm is always yes or no.
          // Anything else on this channel gets a free-text box rather than a dead end,
          // because a string is a valid `response_value` for every type.
          if ( prompt.isYesNo )
            YesNoPromptBody( onRespond: respond, dictate: false )
          else
            OpenEndedPromptBody( onRespond: respond, dictate: false ),
        ],
      ),
    );
  }
}

/// The interview turn: the server is asking and holds a `pending_id` open for the reply.
///
/// The body is the shared `OpenEndedPromptBody`, which is status-blind and knows no endpoint.
/// It takes its own data plus an `onRespond` callback.
/// The host decides, after branching on `status`, whether the value goes to
/// `/api/notify/response`, `/api/v2/resume` or nowhere.
/// Passing a status, an endpoint or a door into a body would fracture that shared shape.
class _InterviewPrompt extends StatelessWidget {
  final QuickAskInterview interview;
  const _InterviewPrompt( { required this.interview } );

  @override
  Widget build( BuildContext context ) {
    final scheme = Theme.of( context ).colorScheme;
    return Container(
      key       : const Key( TestKeys.quickAskInterview ),
      width     : double.infinity,
      color     : scheme.secondaryContainer,
      padding   : const EdgeInsets.all( 12 ),
      child     : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon( Icons.help_outline, size: 18 ),
              const SizedBox( width: 8 ),
              Expanded(
                child: Text(
                  key   : const Key( TestKeys.quickAskInterviewQ ),
                  interview.question,
                  style : const TextStyle( fontWeight: FontWeight.w600 ),
                ),
              ),
              IconButton(
                key       : const Key( TestKeys.quickAskInterviewCancel ),
                icon      : const Icon( Icons.close ),
                tooltip   : 'Cancel',
                onPressed : () => context.read<QuickAskBloc>()
                    .add( const QuickAskInterviewCancelled() ),
              ),
            ],
          ),
          // Keyed by turn.
          // `OpenEndedPromptBody` owns a `TextEditingController` in its state,
          // and the interview re-renders in place on the same `pending_id`.
          // Without a key that changes, Flutter reuses the state and turn 2 opens with turn 1's answer
          // still in the field: "Which day?" pre-filled with "Washington", one Submit from being posted.
          OpenEndedPromptBody(
            key       : ValueKey( '${interview.pendingId}:${interview.turn}' ),
            dictate   : false,   // the bloc owns Quick Ask's recorder (plan §3)
            onRespond : ( text ) => context.read<QuickAskBloc>()
                .add( QuickAskInterviewAnswered( text ) ),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;
  const _InlineError( { required this.message } );

  @override
  Widget build( BuildContext context ) {
    final scheme = Theme.of( context ).colorScheme;
    return Container(
      key       : const Key( TestKeys.quickAskError ),
      width     : double.infinity,
      color     : scheme.errorContainer,
      padding   : const EdgeInsets.all( 12 ),
      child     : Row(
        children: [
          Expanded( child: Text( message, style: TextStyle( color: scheme.onErrorContainer ) ) ),
          IconButton(
            icon      : const Icon( Icons.close ),
            onPressed : () => context.read<QuickAskBloc>().add( const QuickAskErrorDismissed() ),
          ),
        ],
      ),
    );
  }
}

class _LostBanner extends StatelessWidget {
  const _LostBanner();

  @override
  Widget build( BuildContext context ) {
    return Container(
      key     : const Key( TestKeys.quickAskLostBanner ),
      width   : double.infinity,
      color   : Theme.of( context ).colorScheme.errorContainer,
      padding : const EdgeInsets.all( 12 ),
      // Said plainly: updates stopped arriving and the server no longer lists the job anywhere.
      // It does not say "an error occurred".
      child   : const Text( 'Lost track of that question — the server no longer lists it. Try asking again.' ),
    );
  }
}

class _Scrollback extends StatefulWidget {
  final QuickAskState   state;
  final TtsOrchestrator tts;
  const _Scrollback( { required this.state, required this.tts } );

  @override
  State<_Scrollback> createState() => _ScrollbackState();
}

class _ScrollbackState extends State<_Scrollback> {
  /// The scroll controller, owned here so a new interlock surface can be scrolled into view.
  ///
  /// Without a controller the list cannot move itself.
  /// A prepended item then lands above whatever the user was reading.
  final ScrollController _scroll = ScrollController();

  /// How many frames the re-anchor may keep trying for.
  ///
  /// The bound stops it looping; see [_anchorTop].
  static const int _anchorAttempts = 5;

  /// The interlock band as identity tags, in render order.
  ///
  /// The order and conditions match the widgets built in [build].
  /// Widgets cannot be compared across builds, so the decision to re-anchor is taken on these tags.
  ///
  /// Each tag carries the identity of what it stands for, not merely that the slot is occupied.
  /// The interview tag does because turn 2 is a new question on the same `pending_id`.
  /// The error tag does because error B replacing error A is new text the user has not seen.
  /// That holds even when the band is already live and off screen.
  /// `lost` is the one true boolean.
  /// There is one way to be lost, and the banner says the same sentence every time.
  static List<String> _leadingTags( QuickAskState s ) => <String>[
    if ( s.pendingPrompt != null ) 'prompt:${s.pendingPrompt!.id}',
    if ( s.interview != null )     'interview:${s.interview!.pendingId}:${s.interview!.turn}',
    if ( s.errorMessage != null )  'error:${s.errorMessage.hashCode}',
    if ( s.lost )                  'lost',
  ];

  @override
  void didUpdateWidget( covariant _Scrollback old ) {
    super.didUpdateWidget( old );
    // An interlock surface is prepended at index 0, and a `ListView` keeps its pixel offset when that happens.
    // On a list the user has scrolled, the new surface lands entirely above the viewport.
    // The record button then goes inert with "Answer the question above first"
    // pointing at a question that is nowhere on screen, and the confirm times out to its "no".
    // The question must be answerable, and that cannot depend on where the user left the scroll.
    final was = _leadingTags( old.state );
    final now = _leadingTags( widget.state );
    // Anything new in the band: a first surface, a second one beside it,
    // or a fresh question in a slot that was already occupied.
    // Dismissing one removes a tag and moves nothing,
    // so answering a prompt does not yank the list out from under the user.
    if ( now.any( ( t ) => !was.contains( t ) ) ) _anchorTop();
  }

  /// Scrolls to the top so a new interlock surface is visible, retrying for a few frames.
  ///
  /// It uses `jumpTo`, not `animateTo`.
  /// An animation is a race the user can win: a fling in flight cancels it and leaves the question off screen.
  /// The confirm is on a timeout ladder, so the question must be readable the frame it arrives.
  /// The arriving surface is a full-width band, so a jump reads as "something appeared".
  ///
  /// One jump is not enough.
  /// Prepending to a scrolled list makes `RenderSliverList` issue a `scrollOffsetCorrection` at the next layout.
  /// That correction lands after this callback and undoes it.
  /// At 320x568, after dragging up 600 px, a long question settles at 0, which is correct.
  /// A short question settles at 96 with an answer or 172 without, which clips it.
  /// The correction is sized by child extent, so short cards break it, not long lists.
  /// At those offsets the default hard clip hides the question while Yes and No stay tappable.
  /// The user could then answer a question they cannot read.
  ///
  /// So the anchor is re-checked each frame until it holds, capped at [_anchorAttempts] frames.
  /// It stops the moment the list is at the top, and a shape that never settles gives up after five frames.
  void _anchorTop( { int attempt = 0 } ) {
    // After the frame: the new item has not been laid out yet when `didUpdateWidget` runs,
    // and a list that was never scrolled has no attached position to move.
    WidgetsBinding.instance.addPostFrameCallback( ( _ ) {
      if ( !mounted || !_scroll.hasClients ) return;
      final position = _scroll.position;
      if ( position.pixels == position.minScrollExtent ) return;
      if ( attempt >= _anchorAttempts ) return;
      position.jumpTo( position.minScrollExtent );
      _anchorTop( attempt: attempt + 1 );
    } );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build( BuildContext context ) {
    final state = widget.state;

    // The interlock surfaces ride above the cards, in the same scrollable.
    //
    // The confirm prompt stays live while an ask is in flight, though the record button does not,
    // because the ask is blocked on exactly this question.
    // Scrolling keeps it reachable on a small screen, where a fixed child used to push it off.
    //
    // Keep these in lockstep with `_leadingTags` above: same conditions, same order.
    // The tags drive the re-anchor and these draw it.
    final leading = <Widget>[
      if ( state.pendingPrompt != null ) _PendingPrompt( prompt: state.pendingPrompt! ),
      if ( state.interview != null )     _InterviewPrompt( interview: state.interview! ),
      if ( state.errorMessage != null )  _InlineError( message: state.errorMessage! ),
      if ( state.lost )                  const _LostBanner(),
    ];

    // Newest at the top, by the established `.reversed` mechanism and not `reverse: true`.
    // `reverse: true` anchors scroll to the bottom and would fight the pinned header above.
    // `focus_chat_pane.dart` uses the same convention, and nothing in `lib/` uses `reverse: true`.
    final ordered   = state.entries.reversed.toList( growable: false );
    final showEmpty = ordered.isEmpty && state.liveQuestion == null;
    final bodyCount = showEmpty ? 1 : ordered.length;

    return LayoutBuilder(
      builder : ( context, constraints ) => ListView.builder(
        key         : const Key( TestKeys.quickAskList ),
        controller  : _scroll,
        // Zero, not `all( 8 )`: the interlock surfaces are full-bleed colour bands
        // and an inset would break them into floating blocks.
        // The cards carry the horizontal inset themselves, below.
        padding     : EdgeInsets.zero,
        itemCount   : leading.length + bodyCount,
        itemBuilder : ( context, i ) {
          if ( i < leading.length ) return leading[ i ];

          if ( showEmpty ) {
            return SizedBox(
              // With nothing above it, the placeholder owns the whole area and sits dead centre.
              // With a prompt above it, it takes only the room it needs
              // rather than pushing the question it belongs under off the screen.
              height : leading.isEmpty ? constraints.maxHeight : null,
              child  : const Padding(
                padding : EdgeInsets.all( 24 ),
                child   : Center(
                  key   : Key( TestKeys.quickAskEmpty ),
                  child : Text( 'Nothing asked yet.' ),
                ),
              ),
            );
          }

          // `_QuickAskCard` carries a vertical margin of 6 and the list padding is zero,
          // so the first card sits 6 px under the header.
          // Put 8 px back on the first card only, and only when no full-bleed band precedes it.
          // A band is meant to be flush with the header,
          // and the empty-state placeholder sizes itself to `constraints.maxHeight`,
          // so list-level padding would push the idle screen into a needless scroll.
          final firstCard = i == leading.length && leading.isEmpty;
          return Padding(
            padding : EdgeInsets.only( left: 8, right: 8, top: firstCard ? 8 : 0 ),
            child   : _QuickAskCard( entry: ordered[ i - leading.length ], tts: widget.tts ),
          );
        },
      ),
    );
  }
}

class _QuickAskCard extends StatelessWidget {
  final QuickAskEntry   entry;
  final TtsOrchestrator tts;
  const _QuickAskCard( { required this.entry, required this.tts } );

  @override
  Widget build( BuildContext context ) {
    final isDead = entry.lane == JobLane.dead;
    return Card(
      key    : Key( '${TestKeys.quickAskCardPrefix}${entry.jobId ?? "pending"}' ),
      margin : const EdgeInsets.symmetric( vertical: 6 ),
      child  : Padding(
        padding : const EdgeInsets.all( 12 ),
        child   : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Upper-left X.
                // On a card whose job is still running it cancels the job as well as removing the card.
                // The tooltip says which of the two the user is about to get.
                IconButton(
                  key           : Key( '${TestKeys.quickAskCardDismissPrefix}${entry.jobId ?? "pending"}' ),
                  icon          : const Icon( Icons.close, size: 18 ),
                  tooltip       : entry.isTerminal ? 'Remove' : 'Cancel and remove',
                  visualDensity : VisualDensity.compact,
                  constraints   : const BoxConstraints( minWidth: 32, minHeight: 32 ),
                  padding       : EdgeInsets.zero,
                  onPressed     : () => context.read<QuickAskBloc>()
                      .add( QuickAskEntryDismissed( entry.jobId ) ),
                ),
                const SizedBox( width: 4 ),
                _LaneChip( lane: entry.lane ),
                const SizedBox( width: 8 ),
                Expanded( child: Text( entry.questionText,
                    style: const TextStyle( fontWeight: FontWeight.w600 ) ) ),
              ],
            ),
            if ( isDead ) ...[
              const SizedBox( height: 8 ),
              Text(
                // A `needs_input` outcome is terminal and carries no id:
                // the server is telling, not asking.
                // So this card names what was missing and offers no answer control, because there is nothing to answer.
                key   : Key( ( entry.jobId == null || entry.jobId!.isEmpty )
                    ? TestKeys.quickAskNeedsInputCard
                    : '${TestKeys.quickAskErrorCardPrefix}${entry.jobId}' ),
                entry.error ?? 'That question failed.',
                style : TextStyle( color: Theme.of( context ).colorScheme.error ),
              ),
            ] else if ( entry.hasAnswer ) ...[
              const SizedBox( height: 8 ),
              Text(
                key : Key( '${TestKeys.quickAskAnswerPrefix}${entry.jobId ?? "pending"}' ),
                entry.answer!,
              ),
              Align(
                alignment : Alignment.centerRight,
                // Replay goes through the orchestrator's own `replay()`, which calls `resume()` first.
                // An urgent enqueue only preempts when not paused,
                // so a bare enqueue here would play nothing while held,
                // and pause-then-rewind is the natural gesture.
                child     : TextButton.icon(
                  key       : Key( '${TestKeys.quickAskReplayPrefix}${entry.jobId ?? "pending"}' ),
                  icon      : const Icon( Icons.replay, size: 18 ),
                  label     : const Text( 'Replay' ),
                  onPressed : () => tts.replay( message: entry.answer!, title: 'Quick Ask' ),
                ),
              ),
            ] else if ( entry.progressText != null ) ...[
              // A long-running job's milestone is shown so the card visibly breathes.
              // It is a status line in the muted style with a spinner,
              // never in the answer's slot and never styled like an answer.
              // It is the last branch on purpose: an answer or an error always outranks it,
              // so the moment the real result lands this disappears instead of competing with it.
              const SizedBox( height: 8 ),
              Row(
                crossAxisAlignment : CrossAxisAlignment.center,
                children : [
                  const SizedBox(
                    width  : 12,
                    height : 12,
                    child  : CircularProgressIndicator( strokeWidth: 2 ),
                  ),
                  const SizedBox( width: 8 ),
                  Expanded(
                    child : Text(
                      key   : Key( '${TestKeys.quickAskProgressPrefix}${entry.jobId ?? "pending"}' ),
                      entry.progressText!,
                      style : TextStyle(
                        fontStyle : FontStyle.italic,
                        color     : Theme.of( context ).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The status chip, a pure projection of [JobLane].
///
/// It introduces no fourth concept, so a grouped view is `groupBy( entries, (e) => e.state.lane )`
/// with no rework here.
class _LaneChip extends StatelessWidget {
  final JobLane lane;
  const _LaneChip( { required this.lane } );

  @override
  Widget build( BuildContext context ) {
    final scheme = Theme.of( context ).colorScheme;
    late final String   label;
    late final IconData icon;
    late final Color    colour;

    switch ( lane ) {
      case JobLane.todo:
        label = 'Queued';  icon = Icons.schedule;     colour = scheme.outline;
      case JobLane.run:
        label = 'Working'; icon = Icons.autorenew;    colour = scheme.primary;
      case JobLane.done:
        label = 'Answered'; icon = Icons.check_circle; colour = scheme.tertiary;
      case JobLane.dead:
        label = 'Failed';  icon = Icons.error_outline; colour = scheme.error;
    }

    return Chip(
      key             : Key( '${TestKeys.quickAskChipPrefix}${lane.name}' ),
      avatar          : Icon( icon, size: 16, color: colour ),
      label           : Text( label, style: TextStyle( color: colour, fontSize: 12 ) ),
      visualDensity   : VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
