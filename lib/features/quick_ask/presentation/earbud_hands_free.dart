import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/audio/lupin_media_handler.dart';
import '../data/hands_free_cues.dart';
import '../domain/earbud_taps.dart';
import '../domain/quick_ask_bloc.dart';

/// Quick Ask's hands-free mode: while [child] is mounted, the earbuds work record and send.
///
/// A tap starts or stops recording and a double tap sends the held transcript, each with a tone.
/// Mounting takes the earbud presses from the podcast player, and unmounting gives them back.
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
  late final EarbudTapReader _reader = EarbudTapReader( onGesture: _onGesture );

  @override
  void initState() {
    super.initState();
    final handler = widget.handler;
    if ( handler != null ) unawaited( handler.claim( this, card: EarbudHandsFree.card ) );
  }

  @override
  void dispose() {
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
    if ( event != null ) bloc.add( event );
    final cues = widget.cues;
    if ( cues != null ) unawaited( cues.play( action.cue ) );
  }

  @override
  Widget build( BuildContext context ) => widget.child;
}
