import 'dart:async';

import 'package:flutter/material.dart';
import '../../../services/permissions/mic_permission.dart' as mic;

import '../../../core/testing/test_keys.dart';
import '../../../services/asr/asr_service.dart';

enum _VoiceReplyPhase { idle, recording, transcribing, review }

/// Self-contained record→transcribe→edit→send composer (S4 §4.2). The
/// widget NEVER dispatches responses itself (F-S3-2): Send invokes the
/// injected [onSubmit] EXACTLY ONCE with the edited text and resets to
/// idle — S3 wires `onSubmit` to
/// `FocusChatBloc.add( FocusRespondRequested(...) )`, and send-failure
/// surfacing belongs to S2/S3 bloc state, not this widget (the `sending`
/// state was dropped, F-S4-S2-1b).
///
/// State machine: idle → recording (toggle, elapsed indicator) →
/// transcribing (spinner, CANCELABLE — a cellular timeout must never
/// spinner-trap) → review (editable transcript + Send/Cancel) → idle.
/// Any [AsrException] renders the inline error affordance
/// (`TestKeys.voiceReplyError`) and returns to idle — visible feedback,
/// never a vanishing spinner (F-S4-S2-1a).
///
/// Composer AVAILABILITY (the no-pending-prompt gate) is S3's job, off
/// S2's `pendingPromptFor` signal (F-S2-S2-3) — this widget renders
/// wherever embedded.
class VoiceReplyField extends StatefulWidget {
  final AsrService asr;
  final void Function( String text ) onSubmit;

  /// Test seam for the runtime mic-permission request (AC-S4.5). Default
  /// routes through the existing `permission_handler` (F-S4-3 — the
  /// manifest already declares RECORD_AUDIO).
  final Future<bool> Function()? requestMicPermission;

  const VoiceReplyField( {
    super.key,
    required this.asr,
    required this.onSubmit,
    this.requestMicPermission,
  } );

  @override
  State<VoiceReplyField> createState() => _VoiceReplyFieldState();
}

class _VoiceReplyFieldState extends State<VoiceReplyField> {
  _VoiceReplyPhase _phase = _VoiceReplyPhase.idle;
  String? _error;
  final TextEditingController _controller = TextEditingController();

  Timer? _elapsedTimer;
  int    _elapsedSeconds = 0;

  /// Bumped on cancel: an in-flight stopAndTranscribe() result whose epoch
  /// is stale gets dropped instead of resurrecting a cancelled review.
  int _opEpoch = 0;

  /// AC-S2.7 — delegates to the ONE shared requester rather than holding a
  /// private second copy. The widget's `requestMicPermission` test seam is
  /// unchanged; only the default it falls back to moved.
  Future<bool> _defaultMicPermission() => mic.requestMicPermission();

  Future<void> _onMicPressed() async {
    if ( _phase == _VoiceReplyPhase.idle ) {
      setState( () => _error = null );
      final granted =
          await ( widget.requestMicPermission ?? _defaultMicPermission )();
      if ( !mounted ) return;
      if ( !granted ) {
        setState( () => _error =
            'Microphone permission needed — enable it in system settings.' );
        return;
      }
      try {
        await widget.asr.startRecording();
        if ( !mounted ) return;
        setState( () {
          _phase          = _VoiceReplyPhase.recording;
          _elapsedSeconds = 0;
        } );
        _elapsedTimer?.cancel();
        _elapsedTimer = Timer.periodic( const Duration( seconds: 1 ), ( _ ) {
          if ( mounted ) setState( () => _elapsedSeconds++ );
        } );
      } on AsrException catch ( e ) {
        if ( mounted ) setState( () => _error = e.message );
      }
    } else if ( _phase == _VoiceReplyPhase.recording ) {
      _elapsedTimer?.cancel();
      final epoch = _opEpoch;
      setState( () => _phase = _VoiceReplyPhase.transcribing );
      try {
        final transcript = await widget.asr.stopAndTranscribe();
        if ( !mounted || epoch != _opEpoch ) return;   // cancelled mid-flight
        setState( () {
          _controller.text = transcript;
          _phase           = _VoiceReplyPhase.review;
        } );
      } on AsrException catch ( e ) {
        if ( !mounted || epoch != _opEpoch ) return;
        setState( () {
          _error = e.message;
          _phase = _VoiceReplyPhase.idle;
        } );
      }
    }
  }

  void _onCancelPressed() {
    _elapsedTimer?.cancel();
    _opEpoch++;                       // drop any in-flight transcribe result
    if ( _phase == _VoiceReplyPhase.recording ) {
      unawaited( widget.asr.cancelRecording() );
    }
    setState( () {
      _phase = _VoiceReplyPhase.idle;
      _controller.clear();
    } );
  }

  void _onSendPressed() {
    final text = _controller.text.trim();
    if ( text.isEmpty ) return;
    widget.onSubmit( text );          // exactly once — phase resets below
    setState( () {
      _phase = _VoiceReplyPhase.idle;
      _controller.clear();
    } );
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build( BuildContext context ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if ( _error != null )
          Container(
            key     : const Key( TestKeys.voiceReplyError ),
            padding : const EdgeInsets.symmetric( horizontal: 12, vertical: 6 ),
            child   : Row(
              children: [
                Icon( Icons.error_outline,
                    size: 18, color: Theme.of( context ).colorScheme.error ),
                const SizedBox( width: 8 ),
                Expanded( child: Text( _error! ) ),
                IconButton(
                  icon      : const Icon( Icons.close, size: 18 ),
                  tooltip   : 'Dismiss',
                  onPressed : () => setState( () => _error = null ),
                ),
              ],
            ),
          ),
        _buildPhaseRow( context ),
      ],
    );
  }

  Widget _buildPhaseRow( BuildContext context ) {
    switch ( _phase ) {
      case _VoiceReplyPhase.idle:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              key       : const Key( TestKeys.voiceReplyMic ),
              icon      : const Icon( Icons.mic ),
              tooltip   : 'Record a voice reply',
              onPressed : _onMicPressed,
            ),
          ],
        );
      case _VoiceReplyPhase.recording:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              key       : const Key( TestKeys.voiceReplyMic ),
              icon      : const Icon( Icons.stop_circle ),
              tooltip   : 'Stop and transcribe',
              onPressed : _onMicPressed,
            ),
            Text( 'Recording… ${_elapsedSeconds}s' ),
            IconButton(
              key       : const Key( TestKeys.voiceReplyCancel ),
              icon      : const Icon( Icons.delete_outline ),
              tooltip   : 'Discard recording',
              onPressed : _onCancelPressed,
            ),
          ],
        );
      case _VoiceReplyPhase.transcribing:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width  : 20,
              height : 20,
              child  : CircularProgressIndicator( strokeWidth: 2 ),
            ),
            const SizedBox( width: 12 ),
            const Text( 'Transcribing…' ),
            IconButton(
              key       : const Key( TestKeys.voiceReplyCancel ),
              icon      : const Icon( Icons.close ),
              tooltip   : 'Cancel transcription',
              onPressed : _onCancelPressed,
            ),
          ],
        );
      case _VoiceReplyPhase.review:
        return Row(
          children: [
            Expanded(
              child: TextField(
                key        : const Key( TestKeys.voiceReplyTranscript ),
                controller : _controller,
                minLines   : 1,
                maxLines   : 4,
                decoration : const InputDecoration(
                  hintText: 'Edit your reply…',
                ),
              ),
            ),
            IconButton(
              key       : const Key( TestKeys.voiceReplySend ),
              icon      : const Icon( Icons.send ),
              tooltip   : 'Send reply',
              onPressed : _onSendPressed,
            ),
            IconButton(
              key       : const Key( TestKeys.voiceReplyCancel ),
              icon      : const Icon( Icons.close ),
              tooltip   : 'Discard reply',
              onPressed : _onCancelPressed,
            ),
          ],
        );
    }
  }
}
