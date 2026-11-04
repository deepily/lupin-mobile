import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';

/// Small local-time stamp for the lower-left corner of a notification card.
///
/// Shows `HH:mm:ss` in the device's local zone, with a date prefix when the
/// message is not from today.
class MessageStamp extends StatelessWidget {
  /// Moment the message was sent; converted to the device's local zone.
  final DateTime timestamp;

  /// Message id, used to build the test key.
  final String   id;

  /// Creates a stamp for the message [id] sent at [timestamp].
  const MessageStamp( { super.key, required this.timestamp, required this.id } );

  static String _two( int n ) => n < 10 ? '0$n' : '$n';

  /// Formats [ts] as `HH:mm:ss`, or `MM-dd HH:mm:ss` on a different local day.
  ///
  /// [now] defaults to the current time.
  static String format( DateTime ts, { DateTime? now } ) {
    final l = ts.toLocal();
    final n = ( now ?? DateTime.now() ).toLocal();
    final hms = '${_two( l.hour )}:${_two( l.minute )}:${_two( l.second )}';
    final sameDay = l.year == n.year && l.month == n.month && l.day == n.day;
    return sameDay ? hms : '${_two( l.month )}-${_two( l.day )} $hms';
  }

  @override
  Widget build( BuildContext context ) {
    final theme = Theme.of( context );
    return Text(
      format( timestamp ),
      key   : Key( '${TestKeys.messageStampPrefix}$id' ),
      style : theme.textTheme.labelSmall?.copyWith(
        color    : theme.colorScheme.outline,
        fontSize : 10,
        fontFeatures: const [ FontFeature.tabularFigures() ],
      ),
    );
  }
}
