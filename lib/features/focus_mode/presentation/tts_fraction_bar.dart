import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../../../services/notification_audio/notification_preferences.dart';

/// Slider pinned at the top of the focus pane for how much of each message is spoken.
///
/// The fraction runs from 0 to 100 percent in 10 percent steps. At 0 percent only the first
/// sentence is spoken, and at 100 percent the whole message. The bar stays put while the
/// focused conversation changes underneath.
class TtsFractionBar extends StatefulWidget {
  /// The preference store that holds the fraction.
  final NotificationPreferences prefs;

  /// Creates the bar over [prefs].
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
