import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/logging/logger.dart';
import '../../../services/audio/lupin_media_handler.dart';
import '../data/hands_free_cues.dart';
import '../domain/earbud_taps.dart';
import '../domain/quick_ask_bloc.dart';

/// Quick Ask's hands-free mode: while [child] is mounted, the earbuds work record and send.
///
/// A tap starts or stops recording and a double tap sends the held transcript, each with a tone.
/// It holds the earbuds only while Quick Ask is the top screen and the app is on screen.
/// A screen pushed on top, the home button or a locked phone gives them back to the podcast player.
/// With no [handler], as in tests that don't exercise it, this is only [child].
class EarbudHandsFree extends StatefulWidget {
  /// The app's media session; null leaves the earbuds alone.
  final LupinMediaHandler?  handler;
  /// Plays the tone for each gesture; null plays none.
  final HandsFreeCuePlayer? cues;
  /// The Quick Ask screen.
  final Widget              child;

  /// The card the lock screen and notification show while Quick Ask holds the earbuds.
  static const card = MediaItem(
    id     : 'quick-ask-hands-free',
    title  : 'Quick Ask',
    artist : 'Earbud: tap to talk, tap to stop, double tap to send',
  );

  /// Creates the hands-free wrapper.
  const EarbudHandsFree( { super.key, required this.handler, required this.cues, required this.child } );

  @override
  State<EarbudHandsFree> createState() => _EarbudHandsFreeState();
}

class _EarbudHandsFreeState extends State<EarbudHandsFree> implements MediaButtonClaimant {
  late final EarbudTapReader      _reader = EarbudTapReader( onGesture: _onGesture );
  late final AppLifecycleListener _life;
  bool _onTop     = true;
  bool _appShown  = true;
  bool _holding   = false;

  static bool _shown( AppLifecycleState? s ) =>
      s == null || s == AppLifecycleState.resumed || s == AppLifecycleState.inactive;

  @override
  void initState() {
    super.initState();
    _appShown = _shown( WidgetsBinding.instance.lifecycleState );
    _life     = AppLifecycleListener( onStateChange: ( s ) {
      _appShown = _shown( s );
      _sync();
    } );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `ModalRoute.of` rebuilds this when a route is pushed on top or popped back off.
    _onTop = ModalRoute.of( context )?.isCurrent ?? true;
    _sync();
  }

  /// Takes or gives back the earbuds to match whether Quick Ask is in front of the user.
  void _sync() {
    final handler = widget.handler;
    final want    = handler != null && _onTop && _appShown;
    if ( handler == null || want == _holding ) return;
    _holding = want;
    Logger.info( 'hold=$want onTop=$_onTop appShown=$_appShown', tag: LupinMediaHandler.logTag );
    if ( want ) {
      unawaited( handler.claim( this, card: EarbudHandsFree.card ) );
      final cues = widget.cues;
      if ( cues != null ) unawaited( cues.play( HandsFreeCue.ready ) );
    } else {
      _reader.dispose();
      handler.release( this );
    }
  }

  @override
  void dispose() {
    _life.dispose();
    _reader.dispose();
    widget.handler?.release( this );
    super.dispose();
  }

  @override
  void onMediaButton( MediaButton button ) => _reader.press( button );

  void _onGesture( EarbudGesture gesture ) {
    if ( !mounted ) return;
    final bloc   = context.read<QuickAskBloc>();
    final action = earbudAction( gesture, bloc.state );
    final event  = action.event;
    final state  = bloc.state;
    Logger.info( 'gesture: ${ gesture.name } phase=${ state.phase.name } canRecord=${ state.canRecord } '
        'hasDraft=${ state.hasDraft } blocked=${ state.blockReason?.name } -> '
        'event=${ event?.runtimeType } cue=${ action.cue.name }', tag: LupinMediaHandler.logTag );
    if ( event != null ) bloc.add( event );
    final cues = widget.cues;
    if ( cues != null ) unawaited( cues.play( action.cue ) );
  }

  @override
  Widget build( BuildContext context ) => widget.child;
}
