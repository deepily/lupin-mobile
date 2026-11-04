/// The one row schema shared by the task panes.
///
/// Task List and Holding Area render this row, and their cells must be identical,
/// cell for cell. Finished Tasks does not use it: its rows come from `task_events` and
/// carry no priority, blocked, accountable or actions cells. A guard test keeps them
/// apart, see `test/widget/fleet/finished_tasks_does_not_use_task_row_test.dart`.
library;

/// One cell of the shared row.
class RowCell {
  /// The stable identifier tests select on; not the label, which is copy and changes.
  final String key;

  /// The human label shown for the cell.
  final String label;

  /// Creates a cell from its key and label.
  const RowCell( this.key, this.label );
}

/// The schema: three lines of cells, in render order.
///
/// Order is part of the contract: the cell-identity test asserts the ordered key list
/// each pane produces. Line 1 holds only the title and its disclosure control, unlike
/// the web, which packs five fields there. At 360 dp, with 16 dp gutters and a 48 dp
/// control, the title gets about 86 dp, roughly twelve characters. Every fleet title
/// shares the same prefix, so they would all truncate to one string. The app applies no
/// text-scale clamp, so a larger font scale cuts it to about six characters. The other four fields moved to line 2.
class RowSchema {
  RowSchema._();

  /// Line 1: the title only.
  static const line1 = <RowCell>[
    RowCell( 'title', 'Title' ),
  ];

  /// Line 2: identity, state and ownership cells.
  static const line2 = <RowCell>[
    RowCell( 'id',          'ID' ),
    RowCell( 'class',       'Class' ),
    RowCell( 'status',      'Status' ),
    RowCell( 'priority',    'Priority' ),
    RowCell( 'blocked',     'Blocked by' ),
    RowCell( 'chase',       'Next chase' ),
    RowCell( 'accountable', 'Accountable' ),
    RowCell( 'filer',       'Filed by' ),
    RowCell( 'project',     'Project' ),
  ];

  /// Line 3: the detail and the action controls.
  static const line3 = <RowCell>[
    RowCell( 'detail',  'Detail' ),
    RowCell( 'actions', 'Actions' ),
  ];

  /// Every cell, in render order. The panes iterate this, never a hand-written list.
  static const all = <RowCell>[ ...line1, ...line2, ...line3 ];

  /// The ordered key list the cell-identity guard compares against each pane's render.
  static List<String> get keys => all.map( ( c ) => c.key ).toList( growable: false );

  /// The number of cells, derived from [all].
  ///
  /// A literal count would go stale without any visible error when a cell is added.
  static int get cellCount => all.length;
}
