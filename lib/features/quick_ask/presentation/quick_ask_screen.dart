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
              // AC-S4.6 — the Door C interlock. This surface stays LIVE while
              // an ask is in flight (the record button does not), because the
              // ask is blocked on exactly this question.
              if ( state.pendingPrompt != null ) _PendingPrompt( prompt: state.pendingPrompt! ),
              if ( state.interview != null ) _InterviewPrompt( interview: state.interview! ),
              if ( state.errorMessage != null ) _InlineError( message: state.errorMessage! ),
              if ( state.lost ) const _LostBanner(),
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

    return Material(
      elevation : 2,
      child     : Padding(
        padding : const EdgeInsets.symmetric( vertical: 16, horizontal: 12 ),
        child   : Column(
          children: [
            SizedBox(
              width  : 232,
              height : 168,
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
                    child   : _PulsingMic( active: recording, enabled: enabled ),
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
  final bool active;
  final bool enabled;
  const _PulsingMic( { required this.active, required this.enabled } );

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
            width       : 128,
            height      : 128,
            decoration  : BoxDecoration( shape: BoxShape.circle, color: colour ),
            child       : Icon( Icons.mic, size: 60, color: scheme.onPrimary ),
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

class _Scrollback extends StatelessWidget {
  final QuickAskState   state;
  final TtsOrchestrator tts;
  const _Scrollback( { required this.state, required this.tts } );

  @override
  Widget build( BuildContext context ) {
    if ( state.entries.isEmpty && state.liveQuestion == null ) {
      return const Center(
        key   : Key( TestKeys.quickAskEmpty ),
        child : Text( 'Nothing asked yet.' ),
      );
    }

    // NEWEST AT THE TOP (Rick's ruling 3), by the established `.reversed`
    // mechanism — NOT `reverse: true`, which anchors scroll to the BOTTOM and
    // would fight the pinned header above. Same convention as
    // `focus_chat_pane.dart:172-178`; `reverse: true` has zero uses in `lib/`.
    final ordered = state.entries.reversed.toList( growable: false );

    return ListView.builder(
      key         : const Key( TestKeys.quickAskList ),
      padding     : const EdgeInsets.all( 8 ),
      itemCount   : ordered.length,
      itemBuilder : ( context, i ) => _QuickAskCard( entry: ordered[ i ], tts: tts ),
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
