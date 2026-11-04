import 'dart:async';

import 'package:flutter/material.dart';
import '../../../services/asr/voice_capture_session.dart';

import '../../../core/testing/test_keys.dart';
import '../../../services/asr/asr_service.dart';
import '../../../shared/widgets/dictation_text_field.dart';

enum _VoiceReplyPhase { idle, recording, transcribing, review }

/// Minimum height of every composer phase row, in logical pixels.
///
/// It is 25% taller than a stock 48 dp icon-button row so a thumb hits it reliably.
/// The buttons grow to match, so the whole height is a tap target.
const double kVoiceReplyRowHeight = 60.0;   // 48 × 1.25
const double _kIconSize           = 30.0;   // 24 × 1.25
const BoxConstraints _kButtonConstraints = BoxConstraints(
  minWidth  : kVoiceReplyRowHeight,
  minHeight : kVoiceReplyRowHeight,
);

/// Self-contained record, transcribe, edit and send composer.
///
/// The widget never dispatches responses itself: Send calls [onSubmit] once with the edited
/// text and resets to idle. The parent wires `onSubmit` to the bloc, and send-failure
/// surfacing belongs to the bloc state, not to this widget.
///
/// The phases run idle, recording (toggle, elapsed indicator), transcribing, review, then
/// idle again.
/// Transcribing shows a spinner and is cancelable, so a cellular timeout never traps the
/// user. Review shows an editable transcript with Send and Cancel.
/// Any `AsrException` renders the inline error (`TestKeys.voiceReplyError`) and returns to
/// idle, so a failure is never a vanishing spinner.
///
/// Whether the composer is available at all (the no-pending-prompt gate) is the parent's
/// job. This widget renders wherever it is embedded.
class VoiceReplyField extends StatefulWidget {
  /// The speech-recognition service that records and transcribes.
  final AsrService asr;

  /// Called once with the trimmed, edited text when the user taps Send.
  final void Function( String text ) onSubmit;

  /// Test seam for the runtime microphone-permission request.
  ///
  /// The default goes through the existing `permission_handler` plugin.
  final Future<bool> Function()? requestMicPermission;

  /// Creates the composer for [asr], delivering sent text to [onSubmit].
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

  /// Where the review box's append mic stands.
  ///
  /// The mic itself is a [DictationTextField], which owns its recorder session and its
  /// dispose-cancel. This widget only needs the phase, to hide Send while a chunk records.
  DictationPhase _dictation = DictationPhase.idle;

  /// The shared capture session.
  ///
  /// Permission, the cancel epoch, the error strings and the blank-transcript guard live
  /// there, so Quick Ask and this composer behave identically.
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
          // A capture that heard nothing lands here too, so no empty review box opens.
          _error = capture.errorMessage;
          _phase = _VoiceReplyPhase.idle;
        }
      } );
    }
  }

  /// Opens the editor with nothing recorded, so a message can be typed or dictated.
  ///
  /// It is the same review box a transcript lands in, so Send and discard behave as they do
  /// after a recording.
  void _onEditPressed() {
    setState( () {
      _error     = null;
      _dictation = DictationPhase.idle;
      _controller.clear();
      _phase     = _VoiceReplyPhase.review;
    } );
  }

  void _onCancelPressed() {
    _elapsedTimer?.cancel();
    // The review box also opens from the edit button with nothing recorded, and `cancel()`
    // would then cancel a recorder that is not running. Only `recording` owns the recorder.
    // Every other phase calls `invalidate()`, which bumps the same epoch, so an in-flight
    // transcribe result is still dropped and the recorder is left alone.
    if ( _phase == _VoiceReplyPhase.recording ) {
      _session.cancel();              // drops any in-flight transcribe result
    } else {
      _session.invalidate();
    }
    setState( () {
      _phase     = _VoiceReplyPhase.idle;
      _dictation = DictationPhase.idle;
      _controller.clear();
    } );
  }

  void _onSendPressed() {
    final text = _controller.text.trim();
    if ( text.isEmpty ) return;
    widget.onSubmit( text );          // exactly once — phase resets below
    setState( () {
      _phase     = _VoiceReplyPhase.idle;
      _dictation = DictationPhase.idle;
      _controller.clear();
    } );
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    // Leaving mid-recording must cancel the capture, not abandon it. `AsrService` is a
    // singleton, so an abandoned capture would keep TTS's capture hold on for the rest of
    // the app session and make every later `startRecording()` throw.
    //
    // The guard is on `recording` because that is the only phase where this widget owns the
    // recorder, so it cannot cancel a Quick Ask capture on the same shared service.
    // The append mic on the open editor box is a second owner, and it records while
    // `_phase` is `review`; leaving mid-append releases the hold the same way.
    if ( _phase == _VoiceReplyPhase.recording ) {
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
      // Every phase lines up on the right, and the mic and stop button keeps the same corner
      // spot across phases, so the right thumb never moves to stop a recording.
      case _VoiceReplyPhase.idle:
        return Row(
          key              : const Key( TestKeys.voiceReplyIdleRow ),
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // Type instead of dictate, right beside the mic.
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
        // The transcript gets the full width and grows to eight lines before scrolling, with
        // the buttons underneath, so a couple of spoken sentences never read as truncated.
        return Column(
          crossAxisAlignment : CrossAxisAlignment.stretch,
          mainAxisSize       : MainAxisSize.min,
          children: [
            DictationTextField(
              fieldKey   : const Key( TestKeys.voiceReplyTranscript ),
              micKey     : const Key( TestKeys.voiceReplyAppendMic ),
              cancelKey  : const Key( TestKeys.voiceReplyAppendCancel ),
              errorKey   : const Key( TestKeys.voiceReplyError ),
              asr                  : widget.asr,
              requestMicPermission : widget.requestMicPermission,
              micIconSize          : _kIconSize,
              micConstraints       : _kButtonConstraints,
              onPhaseChanged       : ( p ) => setState( () => _dictation = p ),
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

  /// The row under the editor box.
  ///
  /// While a chunk is recording or transcribing the row is hidden, so a thumb cannot send
  /// half a thought by accident.
  Widget _buildReviewButtons() {
    if ( _dictation != DictationPhase.idle ) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
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
