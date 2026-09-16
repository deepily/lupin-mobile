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

/// Quick Ask — tap the button, speak a question, tap again to stop, then send
/// it deliberately and get an answer back, with an honest status indicator in
/// between.
///
/// 🔴 The button is a TAP TOGGLE, not a hold. Holding meant a stumble that
/// broke the press sent a half-finished question; now stopping only parks the
/// transcript, and the small send button under the mic is the only thing that
/// puts it on the wire.
///
/// Layout per Rick's ruling 3: the record button is a FIXED HEADER (not list
/// item 0, so the list below can become round 2's grouped card view untouched),
/// with the scrollback below it and the newest pair on top.
class QuickAskScreen extends StatelessWidget {
  const QuickAskScreen( { super.key } );

  @override
  Widget build( BuildContext context ) {
    // AC-S3.5c — MOUNT seat B's shared control; do not re-implement it. A
    // third `StreamBuilder` over `pausedStream` in this file is the defect
    // that AC exists to prevent, so this screen owns only the mounting.
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
              // A user who paused in focus mode arrives here to a STATED
              // reason rather than a bare icon — the user-visible half of
              // AC-S3.5c. The banner renders nothing when speech is not held.
              TtsPausedBanner(
                tts       : tts,
                bannerKey : const Key( TestKeys.quickAskPausedBanner ),
                reason    : 'Tap replay on an answer to resume.',
              ),
              _RecordHeader( state: state ),
              // Bug 9cddb791 — EVERYTHING below the fixed header scrolls
              // together. The interlock surfaces used to be fixed children of
              // this Column, so on a 320×568 phone the header plus a Door C
              // prompt was already 10px taller than the body, and a prompt
              // plus an error 114px taller: a `Column` cannot shrink a
              // non-flexible child, so it overflowed rather than scrolled.
              // They are now the LEADING ITEMS of the scrollback list (see
              // `_Scrollback`), which is the only arrangement that cannot
              // overflow whatever combination of them is live.
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
    // `canRecord` already goes false while a draft is held, so the mic cannot
    // be tapped out from under a question the user has spoken but not sent.
    final enabled   = state.canRecord;
    final hasDraft  = state.hasDraft;
    // Bug 9cddb791 — while a Door C prompt or an interview turn is live AND
    // the mic is actually inert, a 128px circle is 128px of screen spent on a
    // control that cannot be pressed, taken from the question that is holding
    // the ask open. Shrink it in exactly those states: on a 320×568 phone that
    // is the difference between the whole prompt being on screen and its
    // answer buttons sitting under the fold.
    //
    // 🔴 `!enabled` is LOAD-BEARING, not belt-and-braces. `canRecord` has a
    // `phase == recording` escape hatch (`quick_ask_state.dart:225-226`), and
    // `_onNotification` (`quick_ask_bloc.dart:962-973`) sets `pendingPrompt`
    // with NO phase guard — so a `response_requested` that arrives mid-capture
    // lands on a screen whose mic is the live "tap to stop" control. Shrinking
    // that by a third under a recording user's thumb is a moving target for a
    // gesture already in progress. It stays 128 until the capture ends.
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
            // Rick's ruling (§6 row 2): the send-mode control lives HERE, above
            // the record button. Widget shape from the SegmentedButton in
            // `_ServerContextToggleState.build` (server_context_toggle.dart);
            // the mode itself comes from state, not widget-local state, and a
            // pick goes back through the bloc (J-ABS-2).
            //
            // COMPACT on purpose, and HIDDEN while a Door C prompt or an
            // interview is live: the header is fixed, so every pixel it gains
            // comes out of the column below, and those surfaces must stay on
            // screen (a prompt plus its error overflowed 800×600 by 29px even
            // at compact density). Nothing NEW can be recorded until they are
            // answered, so there is no send mode left to pick. The one gap is
            // a capture already running when the prompt arrived, which keeps
            // whatever mode it started under — this control is render-only
            // (J-ABS-2) and the release path reads `QuickAskPreferences`, so
            // hiding it cannot change that capture's outcome.
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
              // The WIDTH is unchanged so the clear/send buttons keep their
              // corners clear of the circle even at the smaller mic size.
              width  : 232,
              height : stackTall,
              child  : Stack(
                alignment : Alignment.topCenter,
                children  : [
                  GestureDetector(
                    key     : const Key( TestKeys.quickAskRecordButton ),
                    // One tap starts, the next stops. `onTap` and not a long
                    // press: the whole point is that no finger stays down.
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
            // What the send button will actually send. Without it "ready to
            // send" asks the user to trust a transcript they have not seen.
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

/// One of the two small controls flanking the microphone: clear on the lower
/// left, send on the lower right. Deliberately much smaller than the mic — the
/// mic is the thing you aim at, these are the things you confirm with.
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

/// The Door B/C question — a `response_requested` notification that arrived
/// over the WebSocket, rendered while our own ask is still in flight.
///
/// 🔴 Door C's confirm BLOCKS the ask it belongs to (`_user_confirms` holds
/// the HTTP thread, ~210s worst case) and defaults to **"no"** when nobody
/// replies. Before this surface existed the id was recorded, the record button
/// was disabled by it, and the question itself was never shown — so the
/// confirm always expired to "no" and the user saw a mysterious pause. The
/// bodies are the SHARED, door-agnostic ones (AC-S4.11); this host picks the
/// door.
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
                // NOT a local hide — dismissing POSTS the default, so the
                // blocked ask stops waiting instead of burning its ladder.
                tooltip   : 'Dismiss (answers "${prompt.defaultAnswer}")',
                onPressed : () => context.read<QuickAskBloc>()
                    .add( const QuickAskPromptDismissed() ),
              ),
            ],
          ),
          // Door C is always yes/no. Anything else on this channel gets a
          // free-text box rather than a dead end — a string is a valid
          // `response_value` on the notification door for every type.
          if ( prompt.isYesNo )
            YesNoPromptBody( onRespond: respond )
          else
            OpenEndedPromptBody( onRespond: respond ),
        ],
      ),
    );
  }
}

/// The Door-A interview turn — the server is ASKING, and is holding a
/// `pending_id` open for the reply.
///
/// 🔴 The body is the SHARED `OpenEndedPromptBody`, status-blind and
/// door-agnostic. It takes its own data plus an `onRespond` callback and knows
/// nothing about endpoints; the HOST decides — after branching on `status` —
/// whether the value goes to `/api/notify/response`, `/api/v2/resume`, or
/// nowhere. Passing a `status`, an endpoint, or a door into a body is the
/// shape fracturing, which is what AC-S4.11 exists to prevent.
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
          // 🔴 KEYED BY TURN. `OpenEndedPromptBody` owns a
          // `TextEditingController` in its State, and the interview re-renders
          // IN PLACE on the same `pending_id` — so without a key that changes,
          // Flutter reuses the State and turn 2 opens with turn 1's answer
          // still in the field. "Which day?" pre-filled with "Washington",
          // one Submit away from being posted as the day.
          OpenEndedPromptBody(
            key       : ValueKey( '${interview.pendingId}:${interview.turn}' ),
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
      // Said plainly: we stopped hearing about it and the server no longer
      // lists it anywhere. Not "an error occurred".
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
  /// Owned here so a newly-arrived interlock surface can be scrolled back
  /// into view. Without a controller the list has no way to move itself, and
  /// a prepended item silently lands above whatever the user was reading.
  final ScrollController _scroll = ScrollController();

  /// How many frames the re-anchor is allowed to keep trying for. Bounded so
  /// it can never loop: see [_anchorTop].
  static const int _anchorAttempts = 5;

  /// The interlock band as identity TAGS, in render order — the same order
  /// and the same conditions as the widgets built in [build]. Widgets cannot
  /// be compared across builds, so the decision to re-anchor is taken on
  /// these instead.
  ///
  /// Every tag carries the IDENTITY of what it stands for, not merely that
  /// the slot is occupied: the interview because turn 2 is a new question on
  /// the same `pending_id`, and the error because error B replacing error A
  /// in a band that is already live and off screen is new text the user has
  /// not seen. `lost` is the one true boolean — there is only one way to be
  /// lost, and the banner says the same sentence every time.
  static List<String> _leadingTags( QuickAskState s ) => <String>[
    if ( s.pendingPrompt != null ) 'prompt:${s.pendingPrompt!.id}',
    if ( s.interview != null )     'interview:${s.interview!.pendingId}:${s.interview!.turn}',
    if ( s.errorMessage != null )  'error:${s.errorMessage.hashCode}',
    if ( s.lost )                  'lost',
  ];

  @override
  void didUpdateWidget( covariant _Scrollback old ) {
    super.didUpdateWidget( old );
    // Bug 9cddb791 — an interlock surface is PREPENDED at index 0, and a
    // `ListView` keeps its pixel offset when that happens, so on a list the
    // user has scrolled the new surface lands entirely above the viewport.
    // The record button then goes inert with "Answer the question above
    // first" pointing at a question that is nowhere on screen, and Door C
    // times out to its "no" — the very failure `_onNotification` says it
    // fixed by holding the prompt whole rather than by its id. AC-S4.6 asks
    // for an ANSWERABLE question, and answerability cannot depend on where
    // the user happened to leave the scroll.
    final was = _leadingTags( old.state );
    final now = _leadingTags( widget.state );
    // Anything NEW in the band — a first surface, a second one beside it, or
    // a fresh question in a slot that was already occupied. Dismissing one
    // removes a tag and moves nothing, so answering a prompt does not yank
    // the list out from under the user.
    if ( now.any( ( t ) => !was.contains( t ) ) ) _anchorTop();
  }

  /// 🔴 `jumpTo`, not `animateTo`. An animation is a race the user can win:
  /// a fling already in flight cancels it and leaves the question off screen
  /// again, which is the exact bug. Door C is on a timeout ladder, so the
  /// question has to be readable the frame it arrives, not 300ms later. The
  /// arriving surface is a full-width coloured band, so the jump is legible
  /// as "something appeared" without needing the travel to say so.
  ///
  /// 🔴 ONE JUMP IS NOT ENOUGH, and which shapes it fails on is decided by the
  /// scrollback's content rather than by anything in this file. When items are
  /// prepended to a scrolled list, `RenderSliverList` issues a
  /// `scrollOffsetCorrection` during the NEXT layout — it has just measured the
  /// new leading child and is compensating so the old content does not appear
  /// to leap. That correction lands after this callback and undoes it. Measured
  /// at 320x568, dragged up 600px, then a Door C prompt emitted:
  ///
  ///     long question, no answer   frames=[0, 0, 0, …]    settles at 0    ✔
  ///     short question + answer    frames=[0, 96, 96, …]  settles at 96   ✘
  ///     short question, no answer  frames=[0, 172, 172, …] settles at 172 ✘
  ///
  /// The correction is sized by child extent, so it is the same 96 for 6, 12
  /// and 20 cards — short cards, not long lists, are what break it. At 96 the
  /// band's top sits at y=170 with the viewport starting at 266, so `ListView`'s
  /// default hard clip eats the question while leaving Yes and No visible and
  /// tappable. On a door whose dismissal POSTS the default, that is a user
  /// answering a question they cannot read — the same harm as the bug this
  /// re-anchor exists to fix, one layer down.
  ///
  /// So the anchor is re-checked each frame until it holds, capped at
  /// [_anchorAttempts] frames. It stops the moment the list is at the top, and
  /// the cap means a shape that somehow never settles costs five frames and
  /// then gives up rather than spinning forever.
  void _anchorTop( { int attempt = 0 } ) {
    // After the frame: the new item has not been laid out yet when
    // `didUpdateWidget` runs, and a list that has never been scrolled has no
    // attached position to move.
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

    // The interlock surfaces ride ABOVE the cards, in the same scrollable.
    //
    // AC-S4.6 — the Door C interlock. This surface stays LIVE while an ask is
    // in flight (the record button does not), because the ask is blocked on
    // exactly this question. Scrolling is what keeps it reachable on a small
    // screen; being a fixed child is what used to push it off one.
    //
    // 🔴 Kept in lockstep with `_leadingTags` above — same conditions, same
    // order. The tags drive the re-anchor; these draw it.
    final leading = <Widget>[
      if ( state.pendingPrompt != null ) _PendingPrompt( prompt: state.pendingPrompt! ),
      if ( state.interview != null )     _InterviewPrompt( interview: state.interview! ),
      if ( state.errorMessage != null )  _InlineError( message: state.errorMessage! ),
      if ( state.lost )                  const _LostBanner(),
    ];

    // NEWEST AT THE TOP (Rick's ruling 3), by the established `.reversed`
    // mechanism — NOT `reverse: true`, which anchors scroll to the BOTTOM and
    // would fight the pinned header above. Same convention as
    // `focus_chat_pane.dart:172-178`; `reverse: true` has zero uses in `lib/`.
    final ordered   = state.entries.reversed.toList( growable: false );
    final showEmpty = ordered.isEmpty && state.liveQuestion == null;
    final bodyCount = showEmpty ? 1 : ordered.length;

    return LayoutBuilder(
      builder : ( context, constraints ) => ListView.builder(
        key         : const Key( TestKeys.quickAskList ),
        controller  : _scroll,
        // Zero, not `all( 8 )`: the interlock surfaces are full-bleed colour
        // bands and an inset would break them into floating blocks. The cards
        // carry the horizontal inset themselves, below.
        padding     : EdgeInsets.zero,
        itemCount   : leading.length + bodyCount,
        itemBuilder : ( context, i ) {
          if ( i < leading.length ) return leading[ i ];

          if ( showEmpty ) {
            return SizedBox(
              // With nothing above it the placeholder still owns the whole
              // area and sits dead centre, exactly as it did before. With a
              // prompt above it, it takes only the room it needs rather than
              // pushing the question it belongs under off the screen.
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

          // `_QuickAskCard` carries `margin: vertical 6`, and the list padding
          // is now zero, so the first card sits 6px under the header where it
          // used to sit 14 — the 8 came from the list's old `all( 8 )`. Put
          // those 8 back on the first card ONLY, and only when no full-bleed
          // band precedes it: a band is meant to be flush with the header, and
          // the empty-state placeholder sizes itself to `constraints.maxHeight`,
          // so list-level padding would push the idle screen into a needless
          // scroll.
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
                // Upper-left X. On a card whose job is still running this
                // CANCELS it as well as removing it — see the tooltip, which
                // says which of the two the user is about to get.
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
                // A `needs_input` outcome is TERMINAL and carries no id: the
                // server is telling, not asking, so this card names what was
                // missing and offers NO answer affordance — there is nothing
                // to answer to (AC-S4.2).
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
                // Replay goes through the orchestrator's own `replay()`, which
                // calls `resume()` FIRST. An urgent enqueue only preempts when
                // not paused, so a bare enqueue here would play nothing while
                // held — and pause-then-rewind is the natural gesture.
                child     : TextButton.icon(
                  key       : Key( '${TestKeys.quickAskReplayPrefix}${entry.jobId ?? "pending"}' ),
                  icon      : const Icon( Icons.replay, size: 18 ),
                  label     : const Text( 'Replay' ),
                  onPressed : () => tts.replay( message: entry.answer!, title: 'Quick Ask' ),
                ),
              ),
            ] else if ( entry.progressText != null ) ...[
              // Bug 1829eb26, Rick's ruling: a long-running job's milestone is
              // shown so the card visibly breathes — but as a STATUS LINE, in
              // the muted style with a spinner, never in the answer's slot and
              // never styled like one. It is deliberately the LAST branch: an
              // answer or an error always outranks it, so the moment the real
              // result lands this disappears rather than competing with it.
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

/// The status chip is a PURE PROJECTION of [JobLane] — no fourth concept is
/// introduced, so round 2's grouping is `groupBy( entries, (e) => e.state.lane )`
/// with zero rework here.
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
