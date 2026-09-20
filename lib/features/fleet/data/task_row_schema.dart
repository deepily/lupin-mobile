/// The ONE row schema shared by the task panes.
///
/// Port of `multiplexer/render/rowSchema.ts:27-31`. Two mobile panes render this
/// row — Task List and Holding Area — and cell-for-cell identity between them is a
/// behavioural requirement Rick asked for, not a convenience
/// (`holdingAreaTable.ts:20-22`).
///
/// 🔴 FINISHED TASKS IS NOT ONE OF THEM, AND THE PRE-CASCADE PLAN SAID IT WAS.
/// On web the third sharer is the Epic Board (`notifications.js:14873`), which is not
/// a mobile destination. `finishedTasksTable.ts` imports neither `rowSchema` nor
/// `rowDisclosure` and builds its own four-column table, because its rows come from
/// `task_events` and carry no `priority`, no `blocked`, no `accountable` and no
/// `actions`. A guard test pins that apart — see
/// `test/widget/fleet/finished_tasks_does_not_use_task_row_test.dart`.
library;

/// One cell of the shared row.
///
/// `key` is the stable identifier a test selects on. It is deliberately NOT the
/// human label: labels are copy and copy churns, and a selector that tracks copy
/// breaks on an i18n pass.
class RowCell {
  final String key;
  final String label;

  const RowCell( this.key, this.label );
}

/// The schema, three lines, in order.
///
/// ⚠️ ORDER IS PART OF THE CONTRACT. The cell-identity test asserts the ORDERED key
/// list produced by each pane, so a reorder here is a deliberate, visible act rather
/// than something a pane can do to itself.
///
/// 🔴 LINE 1 IS NOT THE WEB'S LINE 1, AND THAT IS MEASURED, NOT PREFERENCE.
/// The web packs `id · title · class · status · priority` onto line 1. At 360 dp —
/// ordinary Android portrait — 16 dp gutters and a 48 dp ellipsis target
/// (`kMinInteractiveDimension`) leave about 86 dp for the title, roughly twelve
/// characters. Every title in this fleet shares a `[LUPIN-MOBILE] Phase N:` prefix, so
/// all of them truncate to the SAME string and the pane cannot be read at all. With
/// the OS font scale raised — the app applies no text-scale clamp, correctly — that
/// falls to about six characters.
///
/// ⇒ Line 1 on a phone is the title and the disclosure control, full stop. The other
/// four line-1 fields move to line 2. The three-line model survives; the
/// five-on-line-1 packing does not.
class RowSchema {
  RowSchema._();

  static const line1 = <RowCell>[
    RowCell( 'title', 'Title' ),
  ];

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

  static const line3 = <RowCell>[
    RowCell( 'detail',  'Detail' ),
    RowCell( 'actions', 'Actions' ),
  ];

  /// Every cell, in render order. The panes iterate THIS, never a hand-written list.
  static const all = <RowCell>[ ...line1, ...line2, ...line3 ];

  /// The ordered key list. The cell-identity guard compares this against what each
  /// pane actually rendered.
  static List<String> get keys => all.map( ( c ) => c.key ).toList( growable: false );

  /// 🔴 DERIVED, NEVER HAND-WRITTEN — carrying `rowWidth()`'s lesson from
  /// `rowSchema.ts:57-71`: *"a stale colspan does not look broken."* A count typed as a
  /// literal goes wrong silently the first time someone adds a cell.
  static int get cellCount => all.length;
}
