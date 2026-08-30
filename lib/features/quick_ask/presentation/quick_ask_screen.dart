import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/service_locator.dart';
import '../../../core/testing/test_keys.dart';
import '../../../services/tts/tts_orchestrator.dart';
import '../../../shared/widgets/tts_pause_control.dart';
import '../../queue/domain/job_lifecycle.dart';
import '../data/quick_ask_models.dart';
import '../domain/quick_ask_bloc.dart';
import '../domain/quick_ask_event.dart';
import '../domain/quick_ask_state.dart';

/// Quick Ask — hold the button, speak a question, release, get an answer back,
/// with an honest status indicator in between.
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
    final bloc    = context.read<QuickAskBloc>();
    final enabled = state.canRecord;
    final holding = state.phase == QuickAskPhase.recording;

    return Material(
      elevation : 2,
      child     : Padding(
        padding : const EdgeInsets.symmetric( vertical: 16, horizontal: 12 ),
        child   : Column(
          children: [
            GestureDetector(
              key                 : const Key( TestKeys.quickAskRecordButton ),
              onLongPressStart    : enabled ? ( _ ) => bloc.add( const QuickAskRecordPressed() )   : null,
              onLongPressEnd      : enabled ? ( _ ) => bloc.add( const QuickAskRecordReleased() )  : null,
              onLongPressCancel   : enabled ? ()    => bloc.add( const QuickAskRecordCancelled() ) : null,
              child               : _PulsingMic( active: holding, enabled: enabled ),
            ),
            const SizedBox( height: 8 ),
            Text( _headline( state ), style: Theme.of( context ).textTheme.bodyMedium ),
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
      case QuickAskPhase.recording:     return 'Listening…';
      case QuickAskPhase.transcribing:  return 'Transcribing…';
      case QuickAskPhase.submitting:    return 'Sending…';
      case QuickAskPhase.waiting:       return 'Working on it…';
      case QuickAskPhase.idle:          return 'Hold to ask';
    }
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
            width       : 96,
            height      : 96,
            decoration  : BoxDecoration( shape: BoxShape.circle, color: colour ),
            child       : Icon( Icons.mic, size: 44, color: scheme.onPrimary ),
          ),
        );
      },
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
              children: [
                _LaneChip( lane: entry.lane ),
                const SizedBox( width: 8 ),
                Expanded( child: Text( entry.questionText,
                    style: const TextStyle( fontWeight: FontWeight.w600 ) ) ),
              ],
            ),
            if ( isDead ) ...[
              const SizedBox( height: 8 ),
              Text(
                key   : Key( '${TestKeys.quickAskErrorCardPrefix}${entry.jobId ?? "pending"}' ),
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
