import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';

/// Small local-time stamp for the lower-left corner of every notification
/// bubble / card (Rick 2026-08-21). `HH:mm:ss` in the device's local zone;
/// a date prefix appears only when the message is not from today.
class MessageStamp extends StatelessWidget {
  final DateTime timestamp;
  final String   id;     // for the test key
  const MessageStamp( { super.key, required this.timestamp, required this.id } );

  static String _two( int n ) => n < 10 ? '0$n' : '$n';

  /// Pure formatter (unit-tested): `HH:mm:ss`, or `MM-dd HH:mm:ss` when
  /// [ts] is not on the same local day as [now].
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
