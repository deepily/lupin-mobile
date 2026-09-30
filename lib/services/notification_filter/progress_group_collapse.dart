/// Pure collapse of CONSECUTIVE items sharing a `progress_group_id`
/// (plan 2026.08.21 §4). This is what the browser gets for free — the
/// Claude Code `Done: <tool>` chatter from `post_tool_use.py` carries a
/// group id so one DOM node absorbs the whole burst; on the phone every
/// item was a bubble. Render-only: the underlying list is never mutated.
class MessageGroup<T> {
  /// The shared progress-group id, or null for an ungrouped single item.
  final String? key;
  final List<T> items;
  const MessageGroup( { required this.key, required this.items } );

  bool get isCollapsed => key != null && items.length > 1;
  T    get latest      => items.last;
  int  get count       => items.length;
}

/// Group [items] in order. [keyOf] returns the progress-group id for an
/// item, or null to keep it as its own row (use this for anything that
/// must never be buried — e.g. a pending ask). Only RUNS of the same
/// non-null key collapse; the same key re-appearing later starts a new
/// group (ordering is preserved exactly). When [enabled] is false every
/// item is its own group.
List<MessageGroup<T>> collapseByProgressGroup<T>(
  List<T> items,
  String? Function( T ) keyOf, {
  bool enabled = true,
} ) {
  final out = <MessageGroup<T>>[];
  for ( final it in items ) {
    final k = enabled ? keyOf( it ) : null;
    if ( k != null && out.isNotEmpty && out.last.key == k ) {
      out[ out.length - 1 ] = MessageGroup<T>( key: k, items: [ ...out.last.items, it ] );
    } else {
      out.add( MessageGroup<T>( key: k, items: [ it ] ) );
    }
  }
  return out;
}
