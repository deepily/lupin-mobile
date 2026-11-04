/// Ordering for the unplayed list the wake chain fetches: oldest first, sorted client-side.
///
/// Design: src/docs/decisions/README.md (R-PUSH-oldest-first)
///
/// The list endpoint's docstring says "sorted by timestamp (newest first)" (`notifications.py`).
/// The handler does no sorting: it walks the queue in insertion order and slices.
/// The documented order and the real order disagree, and this client would be wrong to depend on either.
/// Sorting here costs microseconds on a list of tens and is correct under either behavior.
/// It stays correct if the server later honors its docstring and would otherwise reverse the order.
///
/// The strings are not compared. `NotificationItem.timestamp` is ISO-8601 with a local UTC offset,
/// because the server formats it in the configured timezone (`notification_fifo_queue.py`).
/// It falls back to UTC only when that lookup fails.
/// A restart across a config change or a DST boundary can put a minus-four-hour offset and a UTC
/// timestamp in one list. A lexicographic compare orders them backwards.
/// The timestamps are parsed to instants and compared as instants.
library;

/// Oldest first, by parsed instant, stable.
///
/// Requires:
///   - items are the raw wire maps from the unplayed-list response
///
/// Ensures:
///   - returns a new list; the caller's list is not mutated
///   - items are ordered by their `timestamp` field, earliest first, compared as instants so UTC offsets are honored
///   - an item whose timestamp is missing or unparseable is treated as oldest, so a malformed row is never
///     starved behind well-formed ones
///   - ties (equal instants, or several undateable items) keep their original relative order
///   - never throws
List<Map<String, dynamic>> oldestFirst( List<Map<String, dynamic>> items ) {
  final decorated = <_Dated>[];
  for ( var i = 0; i < items.length; i++ ) {
    decorated.add( _Dated( items[ i ], _instantOf( items[ i ] ), i ) );
  }
  decorated.sort( ( a, b ) {
    final byTime = a.at.compareTo( b.at );
    // The index tiebreak makes the sort stable. Dart's List.sort is not guaranteed stable, so without it
    // two items posted in the same second could swap between runs and a test pinning the order would flake.
    return byTime != 0 ? byTime : a.index.compareTo( b.index );
  } );
  return [ for ( final d in decorated ) d.item ];
}

/// The epoch stands for "no usable timestamp"; see the oldest-first contract.
final DateTime _undateable = DateTime.fromMillisecondsSinceEpoch( 0, isUtc: true );

DateTime _instantOf( Map<String, dynamic> item ) {
  final raw = item[ 'timestamp' ];
  if ( raw is! String || raw.isEmpty ) return _undateable;
  // Use tryParse, not parse: a malformed timestamp must not take down a background handler whose whole job is to still work.
  return DateTime.tryParse( raw )?.toUtc() ?? _undateable;
}

/// A timestamped item with its original index, for the stable sort.
class _Dated {
  final Map<String, dynamic> item;
  final DateTime             at;
  final int                  index;
  const _Dated( this.item, this.at, this.index );
}
