/// The append-mic text box: one shared dictation state machine for every text field.
///
/// The state machine lives here once: idle, listening, transcribing, the splice and cancel
/// on dispose. The append mic is the default behaviour for text boxes in the app.
/// The widget takes the service and builds its own session. It never accepts one, so no
/// ancestor can hand in a session with a foreign lifetime.
/// The two bloc-owned surfaces, Quick Ask and Broadcast, stay outside this widget.
/// Design: src/rnd/2026.09.29-dictation-text-field-plan.md
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/asr/asr_service.dart';
import '../../services/asr/dictation_splice.dart';
import '../../services/asr/voice_capture_session.dart';
import '../../services/permissions/mic_permission.dart';

/// Where a [DictationTextField]'s recording stands.
enum DictationPhase {
  /// No recording is running.
  idle,

  /// The microphone is capturing.
  listening,

  /// The recording is being turned into text.
  transcribing
}

/// Allows one recorder at a time, because [AsrService] is a shared singleton.
///
/// A second mic press while another box records is disabled and never stops the first,
/// because stopping it would silently truncate a sentence.
/// Guards are keyed by service, so they work with or without a [DictationScope].
/// A bloc-owned recorder such as Quick Ask can register here too.
class DictationRecorderGuard extends ChangeNotifier {
  static final Expando<DictationRecorderGuard> _byService = Expando<DictationRecorderGuard>();

  /// The guard for [asr]; the same instance every call.
  static DictationRecorderGuard of( AsrService asr ) =>
      _byService[ asr ] ??= DictationRecorderGuard();

  Object? _owner;

  /// Whoever holds the recorder now, or null when it is free.
  Object? get owner => _owner;

  /// Take the recorder. False when someone else already holds it.
  bool claim( Object who ) {
    if ( _owner != null && _owner != who ) return false;
    if ( _owner == who ) return true;
    _owner = who;
    _notifyLater();
    return true;
  }

  /// Give the recorder back. A no-op unless [who] holds it.
  void release( Object who ) {
    if ( _owner != who ) return;
    _owner = null;
    _notifyLater();
  }

  /// Notifies listeners one microtask later.
  ///
  /// A release can happen inside a widget's dispose, while the tree is torn down, and a
  /// listener's setState is illegal then. The owner value is already set, so only the
  /// repaint waits.
  void _notifyLater() => scheduleMicrotask( () { if ( !_disposed ) notifyListeners(); } );

  bool _disposed = false;

  @override
  void dispose() { _disposed = true; super.dispose(); }
}

/// Hands the [AsrService] to every [DictationTextField] below it.
///
/// It is mounted once at the app root, so no field reaches for `ServiceLocator`.
/// With no scope and no `asr` argument a field renders as a plain TextField.
class DictationScope extends InheritedWidget {
  /// The service handed to fields below, or null for plain text boxes.
  final AsrService? asr;

  /// Replaces the permission prompt for every field below, so tests can stub it.
  final MicPermissionRequester? requestMicPermission;

  /// Creates a scope that provides [asr] to its subtree.
  const DictationScope( {
    super.key,
    required this.asr,
    this.requestMicPermission,
    required super.child,
  } );

  /// The service of the nearest scope, or null when there is none.
  static AsrService? maybeOf( BuildContext context ) =>
      context.dependOnInheritedWidgetOfExactType<DictationScope>()?.asr;

  /// The permission override of the nearest scope, or null.
  static MicPermissionRequester? permissionOf( BuildContext context ) =>
      context.dependOnInheritedWidgetOfExactType<DictationScope>()?.requestMicPermission;

  @override
  bool updateShouldNotify( DictationScope old ) => asr != old.asr;
}

/// A text box with an append mic that adds spoken words to what is typed.
class DictationTextField extends StatefulWidget {
  /// The text being edited; dictated words are spliced into it.
  final TextEditingController controller;

  /// The recorder service.
  ///
  /// Null falls back to [DictationScope]. With neither, this is a plain TextField.
  final AsrService? asr;

  /// Replaces the permission prompt, so tests can stub it.
  final MicPermissionRequester? requestMicPermission;

  /// False forces a plain box even inside a [DictationScope].
  ///
  /// It serves a surface that shares a screen with a bloc-owned recorder, such as Quick
  /// Ask, until that recorder registers with [DictationRecorderGuard].
  final bool dictate;

  /// The caller's decoration.
  ///
  /// The mic is added as `suffixIcon`. If the caller already set one, the mic goes before it.
  final InputDecoration decoration;

  /// Passed to the TextField as `maxLines`.
  final int?             maxLines;

  /// Passed to the TextField as `minLines`.
  final int?             minLines;

  /// Whether the box and its mic accept input.
  final bool             enabled;

  /// Passed to the TextField as `keyboardType`.
  final TextInputType?   keyboardType;

  /// Called on every edit, including a dictated splice.
  final ValueChanged<String>? onChanged;

  /// Passed to the TextField as `onSubmitted`.
  final ValueChanged<String>? onSubmitted;

  /// Passed to the TextField as `focusNode`.
  final FocusNode?       focusNode;

  /// Passed to the TextField as `autofocus`.
  final bool             autofocus;

  /// Key for the text field, so a host screen can find it.
  final Key? fieldKey;

  /// Key for the mic button.
  final Key? micKey;

  /// Key for the cancel button.
  final Key? cancelKey;

  /// Key for the error message, which is then shown as a keyed widget.
  final Key? errorKey;

  /// Tells the host where the recording stands.
  ///
  /// A card uses it to hide Submit while a chunk records.
  final ValueChanged<DictationPhase>? onPhaseChanged;

  /// Icon size for the mic buttons, for a surface with a bigger touch target than 48 dp.
  final double?          micIconSize;

  /// Constraints for the mic buttons, for the same bigger touch target.
  final BoxConstraints?  micConstraints;

  /// Creates a text box, with a mic when a recorder service is available.
  const DictationTextField( {
    super.key,
    required this.controller,
    this.asr,
    this.requestMicPermission,
    this.dictate = true,
    this.decoration = const InputDecoration(),
    this.maxLines = 1,
    this.minLines,
    this.enabled = true,
    this.keyboardType,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
    this.fieldKey,
    this.micKey,
    this.cancelKey,
    this.errorKey,
    this.onPhaseChanged,
    this.micIconSize,
    this.micConstraints,
  } );

  @override
  State<DictationTextField> createState() => _DictationTextFieldState();
}

class _DictationTextFieldState extends State<DictationTextField> {
  DictationPhase _phase = DictationPhase.idle;
  String?        _error;

  int    _caret       = -1;
  String _textAtStart = '';

  Timer? _timer;
  int    _seconds = 0;

  /// True from the mic press until the recorder is running, refused or stale.
  ///
  /// The permission prompt is open meanwhile. Leaving then must still cancel, or the
  /// start completes on a dead widget and strands the recorder.
  bool _starting = false;

  AsrService?            _asr;
  VoiceCaptureSession?   _session;
  DictationRecorderGuard? _guard;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind( _service() );
  }

  AsrService? _service() =>
      widget.dictate ? ( widget.asr ?? DictationScope.maybeOf( context ) ) : null;

  @override
  void didUpdateWidget( DictationTextField old ) {
    super.didUpdateWidget( old );
    if ( widget.asr != old.asr || widget.dictate != old.dictate ) _bind( _service() );
  }

  /// Builds the session once per service, so a recording survives a parent rebuild.
  void _bind( AsrService? asr ) {
    if ( asr == _asr ) return;
    _release();
    _guard?.removeListener( _onGuardChanged );
    _asr     = asr;
    _session = asr == null
        ? null
        : VoiceCaptureSession(
            asr               : asr,
            requestPermission : widget.requestMicPermission ?? DictationScope.permissionOf( context ),
          );
    _guard   = asr == null ? null : DictationRecorderGuard.of( asr );
    _guard?.addListener( _onGuardChanged );
  }

  void _onGuardChanged() { if ( mounted ) setState( () {} ); }

  void _release() {
    _timer?.cancel();
    final s = _session;
    if ( s == null ) return;
    // The recorder is a shared singleton, and abandoning a capture strands the speech hold
    // for the rest of the app session. A running capture is cancelled, and an in-flight
    // transcription is invalidated so its result cannot land on a dead widget.
    if ( _phase == DictationPhase.listening || _starting ) {
      s.cancel();
    } else if ( _phase == DictationPhase.transcribing ) {
      s.invalidate();
    }
    _guard?.release( this );
  }

  @override
  void dispose() {
    _release();
    _guard?.removeListener( _onGuardChanged );
    super.dispose();
  }

  void _setPhase( DictationPhase p ) {
    _phase = p;
    widget.onPhaseChanged?.call( p );
  }

  bool get _blockedByOther {
    final owner = _guard?.owner;
    return owner != null && owner != this;
  }

  Future<void> _onMicPressed() async {
    final session = _session;
    if ( session == null || !widget.enabled ) return;
    if ( _phase == DictationPhase.transcribing ) return;

    if ( _phase == DictationPhase.idle ) {
      if ( !_guard!.claim( this ) ) return;
      setState( () => _error = null );
      final sel    = widget.controller.selection;
      _caret       = sel.isValid ? sel.baseOffset : widget.controller.text.length;
      _textAtStart = widget.controller.text;

      _starting = true;
      final start = await session.start();
      _starting = false;
      if ( !mounted ) return;
      if ( start.isStale ) { _guard!.release( this ); return; }
      if ( !start.started ) {
        _guard!.release( this );
        setState( () => _error = start.errorMessage );
        return;
      }
      setState( () { _setPhase( DictationPhase.listening ); _seconds = 0; } );
      _timer?.cancel();
      _timer = Timer.periodic( const Duration( seconds: 1 ), ( _ ) {
        if ( mounted ) setState( () => _seconds++ );
      } );
      return;
    }

    _timer?.cancel();
    setState( () => _setPhase( DictationPhase.transcribing ) );
    final capture = await session.stopAndTranscribe();
    if ( !mounted ) return;
    _guard!.release( this );
    // A stale result appends nothing but must still free the mic.
    if ( capture.isStale ) {
      setState( () => _setPhase( DictationPhase.idle ) );
      return;
    }
    setState( () {
      if ( capture.wasHeard ) {
        // An edit during the recording voids the remembered caret, so the words go
        // to the end and not into the middle of new text.
        widget.controller.value = spliceDictation(
          value : widget.controller.value,
          heard : capture.transcript!,
          caret : widget.controller.text != _textAtStart ? null : _caret,
        );
        widget.onChanged?.call( widget.controller.text );
      } else {
        _error = capture.errorMessage;
      }
      _setPhase( DictationPhase.idle );
    } );
  }

  void _onCancelPressed() {
    _timer?.cancel();
    if ( _phase == DictationPhase.listening ) {
      _session?.cancel();
    } else {
      _session?.invalidate();
    }
    _guard?.release( this );
    setState( () => _setPhase( DictationPhase.idle ) );
  }

  Widget _micButtons() {
    switch ( _phase ) {
      case DictationPhase.listening:
        return Row( mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            key       : widget.cancelKey,
            icon      : const Icon( Icons.delete_outline ),
            tooltip   : 'Discard this recording',
            onPressed : _onCancelPressed,
            iconSize  : widget.micIconSize,
            constraints: widget.micConstraints,
          ),
          IconButton(
            key       : widget.micKey,
            icon      : const Icon( Icons.stop_circle ),
            tooltip   : 'Stop and add to the box',
            onPressed : _onMicPressed,
            iconSize  : widget.micIconSize,
            constraints: widget.micConstraints,
          ),
        ] );
      case DictationPhase.transcribing:
        return Row( mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            key       : widget.cancelKey,
            icon      : const Icon( Icons.close ),
            tooltip   : 'Cancel transcription',
            onPressed : _onCancelPressed,
            iconSize  : widget.micIconSize,
            constraints: widget.micConstraints,
          ),
          IconButton(
            key       : widget.micKey,
            icon      : const Icon( Icons.mic ),
            onPressed : null,
            iconSize  : widget.micIconSize,
            constraints: widget.micConstraints,
          ),
        ] );
      case DictationPhase.idle:
        return IconButton(
          key       : widget.micKey,
          icon      : const Icon( Icons.mic ),
          tooltip   : 'Dictate',
          onPressed : ( widget.enabled && !_blockedByOther ) ? _onMicPressed : null,
          iconSize  : widget.micIconSize,
          constraints: widget.micConstraints,
        );
    }
  }

  @override
  Widget build( BuildContext context ) {
    var deco = widget.decoration;

    if ( _session != null ) {
      Widget suffix = _micButtons();
      if ( deco.suffixIcon != null ) {
        suffix = Row( mainAxisSize: MainAxisSize.min, children: [ suffix, deco.suffixIcon! ] );
      }
      // A tall box pins the mic to the top right and not the middle of the box.
      if ( widget.maxLines != 1 ) {
        suffix = Align(
          alignment    : Alignment.topCenter,
          widthFactor  : 1,
          heightFactor : 1,
          child        : suffix,
        );
      }

      Widget? helper = deco.helper;
      if ( _phase == DictationPhase.listening ) {
        helper = Text( 'Recording… ${_seconds}s' );
      } else if ( _phase == DictationPhase.transcribing ) {
        helper = const Row( mainAxisSize: MainAxisSize.min, children: [
          SizedBox( width: 16, height: 16, child: CircularProgressIndicator( strokeWidth: 2 ) ),
          SizedBox( width: 8 ),
          Text( 'Transcribing…' ),
        ] );
      }

      deco = deco.copyWith(
        suffixIcon : suffix,
        helper     : helper,
        // Uses errorText when the caller keyed nothing, so the newer dictation message
        // replaces the site's own errorText; otherwise a keyed widget carries it.
        errorText  : _error != null && widget.errorKey == null ? _error : deco.errorText,
        error      : _error != null && widget.errorKey != null
            ? KeyedSubtree( key: widget.errorKey, child: Text( _error! ) )
            : deco.error,
      );
    }

    return TextField(
      key            : widget.fieldKey,
      controller     : widget.controller,
      decoration     : deco,
      maxLines       : widget.maxLines,
      minLines       : widget.minLines,
      enabled        : widget.enabled,
      keyboardType   : widget.keyboardType,
      onChanged      : widget.onChanged,
      onSubmitted    : widget.onSubmitted,
      focusNode      : widget.focusNode,
      autofocus      : widget.autofocus,
    );
  }
}
