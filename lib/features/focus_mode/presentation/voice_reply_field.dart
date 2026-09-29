import 'dart:async';

import 'package:flutter/material.dart';
import '../../../services/asr/voice_capture_session.dart';

import '../../../core/testing/test_keys.dart';
import '../../../services/asr/asr_service.dart';
import '../../../services/asr/dictation_splice.dart';

enum _VoiceReplyPhase { idle, recording, transcribing, review }

/// The microphone ON the open editor box (row 570c2fce), which records ANOTHER
/// chunk and appends it. Its own little state machine, nested inside
/// [_VoiceReplyPhase.review] so the text stays visible and editable throughout:
/// the operator watches the draft he is adding to while he speaks.
enum _AppendMic { idle, listening, transcribing }

/// Rick 2026-09-17: the composer row was too thin to hit reliably with a
/// thumb. Every phase row is 25% taller than a stock 48 dp IconButton row,
/// and its buttons grow to match so the whole height is a tap target.
const double kVoiceReplyRowHeight = 60.0;   // 48 × 1.25
const double _kIconSize           = 30.0;   // 24 × 1.25
const BoxConstraints _kButtonConstraints = BoxConstraints(
  minWidth  : kVoiceReplyRowHeight,
  minHeight : kVoiceReplyRowHeight,
);

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

  /// Row 570c2fce: the append microphone's own phase, and the caret the box held
  /// when that recording began — so the words land where the operator left off
  /// rather than always at the very end.
  _AppendMic _appendMic   = _AppendMic.idle;
  int        _appendCaret = -1;

  /// Row 0b40272e: permission, the cancel epoch, the error strings and the
  /// blank-transcript guard are no longer this widget's own — they live in the
  /// shared session, so Quick Ask and this composer cannot drift again.
  late final VoiceCaptureSession _session = VoiceCaptureSession(
    asr                : widget.asr,
    requestPermission  : widget.requestMicPermission,
  );

  Future<void> _onMicPressed() async {
    if ( _phase == _VoiceReplyPhase.idle ) {
      setState( () => _error = null );
      final start = await _session.start();
      if ( !mounted || start.isStale ) return;
      if ( !start.started ) {
        setState( () => _error = start.errorMessage );
        return;
      }
      setState( () {
        _phase          = _VoiceReplyPhase.recording;
        _elapsedSeconds = 0;
      } );
      _elapsedTimer?.cancel();
      _elapsedTimer = Timer.periodic( const Duration( seconds: 1 ), ( _ ) {
        if ( mounted ) setState( () => _elapsedSeconds++ );
      } );
    } else if ( _phase == _VoiceReplyPhase.recording ) {
      _elapsedTimer?.cancel();
      setState( () => _phase = _VoiceReplyPhase.transcribing );
      final capture = await _session.stopAndTranscribe();
      if ( !mounted || capture.isStale ) return;   // cancelled mid-flight
      setState( () {
        if ( capture.wasHeard ) {
          _controller.text = capture.transcript!;
          _phase           = _VoiceReplyPhase.review;
        } else {
          // Including a capture that heard NOTHING, which used to open an
          // empty review box with a live Send button behind it.
          _error = capture.errorMessage;
          _phase = _VoiceReplyPhase.idle;
        }
      } );
    }
  }

  /// Row 8cc964ec (Rick 2026-09-26): open the editor with nothing recorded,
  /// so a message can be typed — or dictated with the keyboard's own mic.
  /// It is the same review box a transcript lands in, so Send and discard
  /// behave exactly as they do after a recording.
  void _onEditPressed() {
    setState( () {
      _error     = null;
      _appendMic = _AppendMic.idle;
      _controller.clear();
      _phase     = _VoiceReplyPhase.review;
    } );
  }

  /// Record one MORE chunk into the open editor box, and append it (row
  /// 570c2fce). The toggle is the same shape as the idle mic's — tap to record,
  /// tap to stop and transcribe — but it never touches [_phase]: the box, its
  /// text and the caret survive every outcome, including a refusal, a cancel, a
  /// transcription failure and a capture that heard nothing.
  Future<void> _onAppendMicPressed() async {
    if ( _appendMic == _AppendMic.transcribing ) return;

    if ( _appendMic == _AppendMic.idle ) {
      setState( () => _error = null );
      final sel    = _controller.selection;
      _appendCaret = sel.isValid ? sel.baseOffset : _controller.text.length;
      final start  = await _session.start();
      if ( !mounted || start.isStale ) return;
      if ( !start.started ) {
        setState( () => _error = start.errorMessage );
        return;
      }
      setState( () {
        _appendMic      = _AppendMic.listening;
        _elapsedSeconds = 0;
      } );
      _elapsedTimer?.cancel();
      _elapsedTimer = Timer.periodic( const Duration( seconds: 1 ), ( _ ) {
        if ( mounted ) setState( () => _elapsedSeconds++ );
      } );
      return;
    }

    _elapsedTimer?.cancel();
    setState( () => _appendMic = _AppendMic.transcribing );
    final capture = await _session.stopAndTranscribe();
    if ( !mounted ) return;
    // A stale result appends NOTHING — but it must still free the mic, or every
    // later tap is dead (the New Ticket card's own lesson, review of 30efd26).
    if ( capture.isStale ) {
      setState( () => _appendMic = _AppendMic.idle );
      return;
    }
    setState( () {
      if ( capture.wasHeard ) {
        _controller.value = spliceDictation(
          value : _controller.value,
          heard : capture.transcript!,
          caret : _appendCaret,
        );
      } else {
        // Including silence: the draft is left exactly as it was, and the
        // operator is told why nothing arrived.
        _error = capture.errorMessage;
      }
      _appendMic = _AppendMic.idle;
    } );
  }

  /// Discard the chunk being recorded — NOT the draft. The editor box and its
  /// text come back untouched.
  void _onAppendCancelPressed() {
    _elapsedTimer?.cancel();
    if ( _appendMic == _AppendMic.listening ) {
      _session.cancel();            // the recorder is running; stop and discard it
    } else {
      _session.invalidate();        // transcribing: drop the result, nothing to stop
    }
    setState( () => _appendMic = _AppendMic.idle );
  }

  void _onCancelPressed() {
    _elapsedTimer?.cancel();
    // Row a1c12c6e (review LOW): the review box also opens from the edit
    // button, with nothing ever recorded — `cancel()` would then call
    // `cancelRecording()` on a recorder that is not running. `recording` is
    // the only phase that still owns the recorder; everywhere else
    // `invalidate()` bumps the SAME epoch, so an in-flight transcribe result
    // is dropped just as before, and the recorder is left alone.
    if ( _phase == _VoiceReplyPhase.recording ) {
      _session.cancel();              // drops any in-flight transcribe result
    } else {
      _session.invalidate();
    }
    setState( () {
      _phase     = _VoiceReplyPhase.idle;
      _appendMic = _AppendMic.idle;
      _controller.clear();
    } );
  }

  void _onSendPressed() {
    final text = _controller.text.trim();
    if ( text.isEmpty ) return;
    widget.onSubmit( text );          // exactly once — phase resets below
    setState( () {
      _phase     = _VoiceReplyPhase.idle;
      _appendMic = _AppendMic.idle;
      _controller.clear();
    } );
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    // Row a1c12c6e (review FAIL): navigating away mid-recording used to
    // ABANDON the capture rather than cancel it. `AsrService` is a singleton,
    // so `_activePath` outlived this widget, TTS's capture hold stayed on for
    // the rest of the app session with no indicator, and every later
    // `startRecording()` threw 'A recording is already in progress'.
    //
    // Guarded on `recording` because that is the only phase where this widget
    // still owns the recorder — the guard cannot cancel a Quick Ask capture
    // running on the same shared service. Row 570c2fce added a SECOND place
    // this widget owns it: the append mic on the open editor box, which records
    // while `_phase` says `review`. Leaving mid-append has to release the hold
    // for exactly the same reason.
    if ( _phase == _VoiceReplyPhase.recording || _appendMic == _AppendMic.listening ) {
      _session.cancel();
    }
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
        ConstrainedBox(
          constraints : const BoxConstraints( minHeight: kVoiceReplyRowHeight ),
          child       : _buildPhaseRow( context ),
        ),
      ],
    );
  }

  Widget _buildPhaseRow( BuildContext context ) {
    switch ( _phase ) {
      // Row 3f2a7dab (Rick 2026-09-26): the buttons sat bottom-CENTRE, on the
      // fold of his phone. Every phase now lines up on the RIGHT, and the
      // mic/stop button keeps the same corner spot across phases, so the
      // right thumb never has to move to stop a recording.
      case _VoiceReplyPhase.idle:
        return Row(
          key              : const Key( TestKeys.voiceReplyIdleRow ),
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // Row 8cc964ec: type instead of dictate, right beside the mic.
            IconButton(
              key         : const Key( TestKeys.voiceReplyEdit ),
              icon        : const Icon( Icons.edit ),
              tooltip     : 'Type a message',
              onPressed   : _onEditPressed,
              iconSize    : _kIconSize,
              constraints : _kButtonConstraints,
            ),
            IconButton(
              key         : const Key( TestKeys.voiceReplyMic ),
              icon        : const Icon( Icons.mic ),
              tooltip     : 'Record a voice reply',
              onPressed   : _onMicPressed,
              iconSize    : _kIconSize,
              constraints : _kButtonConstraints,
            ),
          ],
        );
      case _VoiceReplyPhase.recording:
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text( 'Recording… ${_elapsedSeconds}s' ),
            IconButton(
              key         : const Key( TestKeys.voiceReplyCancel ),
              icon        : const Icon( Icons.delete_outline ),
              tooltip     : 'Discard recording',
              onPressed   : _onCancelPressed,
              iconSize    : _kIconSize,
              constraints : _kButtonConstraints,
            ),
            IconButton(
              key         : const Key( TestKeys.voiceReplyMic ),
              icon        : const Icon( Icons.stop_circle ),
              tooltip     : 'Stop and transcribe',
              onPressed   : _onMicPressed,
              iconSize    : _kIconSize,
              constraints : _kButtonConstraints,
            ),
          ],
        );
      case _VoiceReplyPhase.transcribing:
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const SizedBox(
              width  : 20,
              height : 20,
              child  : CircularProgressIndicator( strokeWidth: 2 ),
            ),
            const SizedBox( width: 12 ),
            const Text( 'Transcribing…' ),
            IconButton(
              key         : const Key( TestKeys.voiceReplyCancel ),
              icon        : const Icon( Icons.close ),
              tooltip     : 'Cancel transcription',
              onPressed   : _onCancelPressed,
              iconSize    : _kIconSize,
              constraints : _kButtonConstraints,
            ),
          ],
        );
      case _VoiceReplyPhase.review:
        // Row 0b40272e: the transcript used to share ONE row with both
        // buttons, four lines tall — a couple of spoken sentences ran out of
        // room and read as truncated. It now gets the full width and grows to
        // eight lines before scrolling, with the buttons underneath.
        return Column(
          crossAxisAlignment : CrossAxisAlignment.stretch,
          mainAxisSize       : MainAxisSize.min,
          children: [
            TextField(
              key        : const Key( TestKeys.voiceReplyTranscript ),
              controller : _controller,
              // Opened by the edit button there is nothing to review, so the
              // keyboard comes straight up.
              autofocus  : _controller.text.isEmpty,
              minLines   : 2,
              maxLines   : 8,
              keyboardType : TextInputType.multiline,
              decoration : const InputDecoration(
                hintText  : 'Edit your reply…',
                isDense   : true,
                border    : OutlineInputBorder(),
                contentPadding : EdgeInsets.symmetric( horizontal: 10, vertical: 8 ),
              ),
            ),
            const SizedBox( height: 4 ),
            _buildReviewButtons(),
          ],
        );
    }
  }

  /// The row under the editor box. Row 570c2fce put a microphone on it, so the
  /// row now has three faces — and while a chunk is recording or transcribing,
  /// Send is NOT one of them: a thumb cannot send half a thought by accident.
  Widget _buildReviewButtons() {
    switch ( _appendMic ) {
      case _AppendMic.listening:
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text( 'Recording… ${_elapsedSeconds}s' ),
            IconButton(
              key         : const Key( TestKeys.voiceReplyAppendCancel ),
              icon        : const Icon( Icons.delete_outline ),
              tooltip     : 'Discard this recording',
              onPressed   : _onAppendCancelPressed,
              iconSize    : _kIconSize,
              constraints : _kButtonConstraints,
            ),
            IconButton(
              key         : const Key( TestKeys.voiceReplyAppendMic ),
              icon        : const Icon( Icons.stop_circle ),
              tooltip     : 'Stop and add to the reply',
              onPressed   : _onAppendMicPressed,
              iconSize    : _kIconSize,
              constraints : _kButtonConstraints,
            ),
          ],
        );
      case _AppendMic.transcribing:
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const SizedBox(
              width  : 20,
              height : 20,
              child  : CircularProgressIndicator( strokeWidth: 2 ),
            ),
            const SizedBox( width: 12 ),
            const Text( 'Transcribing…' ),
            IconButton(
              key         : const Key( TestKeys.voiceReplyAppendCancel ),
              icon        : const Icon( Icons.close ),
              tooltip     : 'Cancel transcription',
              onPressed   : _onAppendCancelPressed,
              iconSize    : _kIconSize,
              constraints : _kButtonConstraints,
            ),
          ],
        );
      case _AppendMic.idle:
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              key         : const Key( TestKeys.voiceReplyAppendMic ),
              icon        : const Icon( Icons.mic ),
              tooltip     : 'Add more by voice',
              onPressed   : _onAppendMicPressed,
              iconSize    : _kIconSize,
              constraints : _kButtonConstraints,
            ),
            IconButton(
              key         : const Key( TestKeys.voiceReplyCancel ),
              icon        : const Icon( Icons.close ),
              tooltip     : 'Discard reply',
              onPressed   : _onCancelPressed,
              iconSize    : _kIconSize,
              constraints : _kButtonConstraints,
            ),
            IconButton(
              key         : const Key( TestKeys.voiceReplySend ),
              icon        : const Icon( Icons.send ),
              tooltip     : 'Send reply',
              onPressed   : _onSendPressed,
              iconSize    : _kIconSize,
              constraints : _kButtonConstraints,
            ),
          ],
        );
    }
  }
}
