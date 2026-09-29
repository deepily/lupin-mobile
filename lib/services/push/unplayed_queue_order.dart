/// Ordering for the unplayed-notification list the wake chain fetches
/// (Tiffany's ruling, 2026-09-28: sort ascending by timestamp, client-side).
///
/// 🔴 WHY THE CLIENT SORTS AT ALL, WHEN THE SERVER APPEARS TO. The list
/// endpoint's docstring says it returns notifications "sorted by timestamp
/// (newest first)" — `notifications.py:2520`. The handler does no sorting
/// whatsoever (`notifications.py:2536`): it walks the queue in insertion order
/// and slices. So the documented order and the real order disagree, and BOTH
/// are things this client would be wrong to depend on. Sorting here costs
/// microseconds on a list of tens and makes the chain correct under either
/// server behaviour — including a future server-side fix that finally honours
/// its own docstring and reverses us.
///
/// 🔴 WHY NOT COMPARE THE STRINGS. `NotificationItem.timestamp` is an
/// ISO-8601 string carrying a LOCAL UTC OFFSET — the server formats it in the
/// configured timezone (`notification_fifo_queue.py:149`) and only falls back
/// to UTC when that lookup fails. So one process restart across a config
/// change, or a DST boundary, is enough to put `...T01:00-04:00` and
/// `...T02:00+00:00` in the same list, where a lexicographic compare orders
/// them backwards. These are parsed to instants and compared as instants.
library;

/// Oldest first, by parsed instant, stable.
///
/// Requires:
///     - items are the raw wire maps from the unplayed-list response
///
/// Ensures:
///     - returns a NEW list; the caller's list is not mutated
///     - items are ordered by their `timestamp` field, earliest first,
///       compared as instants so UTC offsets are honoured
///     - an item whose timestamp is missing or unparseable is treated as
///       OLDEST, so a malformed row is never starved behind well-formed ones
///     - ties (equal instants, or several undateable items) keep their
///       original relative order
///     - never throws
List<Map<String, dynamic>> oldestFirst( List<Map<String, dynamic>> items ) {
  final decorated = <_Dated>[];
  for ( var i = 0; i < items.length; i++ ) {
    decorated.add( _Dated( items[ i ], _instantOf( items[ i ] ), i ) );
  }
  decorated.sort( ( a, b ) {
    final byTime = a.at.compareTo( b.at );
    // The index tiebreak is what makes this stable. Dart's List.sort is NOT
    // guaranteed stable, so without it two items posted in the same second
    // could swap between runs and a test pinning the order would flake.
    return byTime != 0 ? byTime : a.index.compareTo( b.index );
  } );
  return [ for ( final d in decorated ) d.item ];
}

/// Epoch stands for "no usable timestamp" — see the oldest-first contract.
final DateTime _undateable = DateTime.fromMillisecondsSinceEpoch( 0, isUtc: true );

DateTime _instantOf( Map<String, dynamic> item ) {
  final raw = item[ 'timestamp' ];
  if ( raw is! String || raw.isEmpty ) return _undateable;
  // tryParse, not parse: a malformed timestamp must not take down a background
  // handler whose whole job is to be the thing that still works.
  return DateTime.tryParse( raw )?.toUtc() ?? _undateable;
}

class _Dated {
  final Map<String, dynamic> item;
  final DateTime             at;
  final int                  index;
  const _Dated( this.item, this.at, this.index );
}
