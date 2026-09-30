import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../../../services/notification_audio/notification_preferences.dart';

/// TTS preview-fraction slider pinned at the top of the focus pane (Rick
/// 2026-08-21; mirrors the web client's `#cc-tts-fraction-slider`): how much
/// of each message is spoken automatically, 0-100% in 10% steps. Stays put
/// while the focused conversation changes underneath. 0% = first sentence
/// only; 100% = whole message.
class TtsFractionBar extends StatefulWidget {
  final NotificationPreferences prefs;
  const TtsFractionBar( { super.key, required this.prefs } );

  @override
  State<TtsFractionBar> createState() => _TtsFractionBarState();
}

class _TtsFractionBarState extends State<TtsFractionBar> {
  late double _fraction = widget.prefs.ttsFraction;

  void _onChanged( double v ) {
    final snapped = NotificationPreferences.snapTtsFraction( v );
    setState( () => _fraction = snapped );
    widget.prefs.setTtsFraction( snapped );
  }

  @override
  Widget build( BuildContext context ) {
    final theme = Theme.of( context );
    final pct   = ( _fraction * 100 ).round();
    return Material(
      key   : const Key( TestKeys.focusTtsFractionBar ),
      color : theme.colorScheme.surfaceContainerLow,
      child : Padding(
        padding: const EdgeInsets.fromLTRB( 12, 0, 8, 0 ),
        child: Row(
          children: [
            Icon( Icons.record_voice_over_outlined, size: 16, color: theme.colorScheme.outline ),
            const SizedBox( width: 6 ),
            Text( 'TTS', style: theme.textTheme.labelSmall ),
            Expanded(
              child: Slider(
                key       : const Key( TestKeys.focusTtsFractionSlider ),
                value     : _fraction,
                min       : 0,
                max       : 1,
                divisions : 10,
                label     : '$pct%',
                onChanged : _onChanged,
              ),
            ),
            SizedBox(
              width: 40,
              child: Text( '$pct%',
                key       : const Key( TestKeys.focusTtsFractionValue ),
                textAlign : TextAlign.right,
                style     : theme.textTheme.labelMedium ),
            ),
          ],
        ),
      ),
    );
  }
}
