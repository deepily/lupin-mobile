/// A run of consecutive items that share a `progress_group_id`, or one ungrouped item.
///
/// The Claude Code `Done: <tool>` chatter from `post_tool_use.py` carries a group id.
/// A browser node absorbs the whole burst, while the phone otherwise shows one bubble per item.
/// Grouping is render-only: the underlying list is never mutated.
class MessageGroup<T> {
  /// The shared progress-group id, or null for an ungrouped single item.
  final String? key;
  /// The items in this group, in their original order.
  final List<T> items;
  /// Creates a group.
  const MessageGroup( { required this.key, required this.items } );

  /// True when the group has a key and more than one item.
  bool get isCollapsed => key != null && items.length > 1;
  /// The last item in the group.
  T    get latest      => items.last;
  /// Number of items in the group.
  int  get count       => items.length;
}

/// Groups [items] into runs of the same progress-group key, preserving order.
///
/// [keyOf] returns the group id for an item. It returns null to keep an item as its own row,
/// for anything that must not be buried, such as a pending ask. Only a run of the same non-null key collapses; the same key
/// reappearing later starts a new group. When [enabled] is false every item is its own group.
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
