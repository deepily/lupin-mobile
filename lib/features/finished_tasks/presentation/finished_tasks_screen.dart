import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/testing/test_keys.dart';
import '../data/finished_tasks_models.dart';
import '../domain/finished_tasks_bloc.dart';
import '../domain/finished_tasks_event.dart';
import '../domain/finished_tasks_state.dart';

/// The Finished Tasks pane — what just got done, by whom, and why it closed.
///
/// 🔴 THIS PANE BUILDS ITS OWN ROW AND MUST KEEP DOING SO. Its rows are
/// `task_events`: they carry no `priority`, no `blocked`, no `accountable` and no
/// `actions`, so the shared `TaskRow` would render ten fields this data does not
/// have. The web source is structural about it — `finishedTasksTable.ts` imports
/// neither `rowSchema` nor `rowDisclosure`.
///
/// ⚠️ IF YOU ARE HERE TO TIDY AN INCONSISTENCY, READ THIS FIRST. §7.1 of the plan
/// says "Do not give this pane a row of its own" — that sentence is about the HOLDING
/// AREA, under a heading called "The shared row", and taken cold it reads as a
/// mandate to unify. It is not. The widget test asserts the absence of `TaskRow`
/// NEGATIVELY so that unifying them fails ON the refactor rather than after it.
class FinishedTasksScreen extends StatefulWidget {
  const FinishedTasksScreen( { super.key } );

  @override
  State<FinishedTasksScreen> createState() => _FinishedTasksScreenState();
}

class _FinishedTasksScreenState extends State<FinishedTasksScreen> {
  /// 🔴 THE FIRST LOAD. Without this the pane is a spinner forever.
  ///
  /// Found on hardware 2026-09-22 (Rick, emulator walk-through item 7): open the pane and
  /// it shows nothing but a `CircularProgressIndicator`, and the logcat carries **no
  /// request to `/api/tasks/events` at all** — the absence was the evidence.
  ///
  /// This screen was a `StatelessWidget` whose `BlocBuilder` renders a spinner for
  /// `FinishedTasksInitial`, and every dispatcher of `FinishedTasksRequested` was
  /// user-initiated: the refresh button, the error view's retry, pull-to-refresh, and the
  /// window slider. Nothing fired on mount — not the screen, not the `BlocProvider`'s
  /// `create:`, not `ServiceLocator.buildFinishedTasksBloc()`. The bloc's own class comment
  /// lists "first load" among the triggers it refetches on; **nobody was sending it.**
  ///
  /// ⚠️ And 15 widget tests passed the whole time, because each one seeds the state it
  /// wants to render. A test that hands the bloc a `FinishedTasksLoaded` proves the table
  /// draws; it cannot prove anyone asked for the data. Same shape as the orphan panes and
  /// the ack dispatch — the trigger and the render are different things.
  ///
  /// Matches the idiom the other fleet panes already use (`task_list_pane.dart:38`):
  /// route-scoped, so it is on screen the moment it is built.
  /// 🔴 HELD, NOT LOOKED UP IN `dispose()`. `context.read` walks the element tree, and by
  /// the time `dispose` runs that element is being torn down — the lookup can throw, and a
  /// throw there SKIPS the rest of dispose. The timer then outlives the pane that owned
  /// it: a poll firing against a screen nobody is looking at, for the life of the process.
  ///
  /// ⚠️ That bug is almost unattributable in the field — it costs battery and data with no
  /// visible symptom, on a pane the user has already left. Found by Chloé in Phase 1 and
  /// carried by every pane that polls; this one joins them.
  late final FinishedTasksBloc _bloc;

  @override
  void initState() {
    super.initState();
    _bloc = context.read<FinishedTasksBloc>()..startPolling();
    // 🔴 `onPaneVisible()` IS THE FIRST LOAD, AND THERE IS DELIBERATELY NO SECOND
    // TRIGGER BESIDE IT. The mixin refreshes immediately when a pane appears, so a
    // `FinishedTasksRequested` here as well would make mounting this pane issue TWO
    // window fetches — six HTTP calls, since the window is one request per status — and
    // `finished_tasks_first_load_test.dart` asserts exactly one.
    //
    // ⚠️ THE HARDWARE BUG THAT TEST GUARDS IS STILL GUARDED. Rick's symptom was a
    // spinner forever with no request on the wire; what fixed it was the pane asking for
    // its own data on mount, not the particular event it asked with. It still asks —
    // `FinishedTasksInitial` renders the spinner until the answer lands, and a FAILED
    // first load still paints the error view, because the poll path stays silent only
    // once there are rows to keep. See `FinishedTasksBloc._onPolled`.
    _bloc.onPaneVisible();
  }

  @override
  void dispose() {
    _bloc.onPaneHidden();
    super.dispose();
  }

  @override
  Widget build( BuildContext context ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text( "Finished Tasks" ),
        actions: [
          // ⚠️ A REFRESH BUTTON, NOT ONLY PULL-TO-REFRESH. `RefreshIndicator` has no
          // semantic action that a screen reader can invoke — its only accessibility
          // parameters describe the spinner once a refresh is already running — and
          // the pull itself is a drag TalkBack does not pass through. Without this
          // button, refreshing this pane is a verb a screen-reader user cannot reach.
          IconButton(
            key     : const Key( TestKeys.finishedRefreshButton ),
            tooltip : "Refresh",
            icon    : const Icon( Icons.refresh ),
            onPressed: () => context
                .read<FinishedTasksBloc>()
                .add( const FinishedTasksRequested() ),
          ),
        ],
      ),
      body: BlocBuilder<FinishedTasksBloc, FinishedTasksState>(
        builder: ( context, state ) {
          if ( state is FinishedTasksInitial || state is FinishedTasksLoading ) {
            return const Center( child: CircularProgressIndicator() );
          }
          if ( state is FinishedTasksError ) {
            return _ErrorView(
              message : state.message,
              onRetry : () => context
                  .read<FinishedTasksBloc>()
                  .add( const FinishedTasksRequested() ),
            );
          }
          final loaded = state as FinishedTasksLoaded;
          return RefreshIndicator(
            onRefresh: () async => context
                .read<FinishedTasksBloc>()
                .add( const FinishedTasksRequested() ),
            child: Column(
              children: [
                _FilterPills( state: loaded ),
                _WindowControl( days: loaded.days ),
                if ( loaded.isPartial ) _PartialBanner( result: loaded.result ),
                Expanded( child: _RowList( rows: loaded.rows ) ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The three status pills.
///
/// ⚠️ A PILL'S COUNT DOES NOT DEPEND ON WHETHER IT IS LIT. An unlit status withholds
/// its rows from the table and still shows how many it has — otherwise the only way
/// to discover that eleven rows were closed as won't-fix is to light the pill, which
/// is the discovery this pane exists to make unnecessary.
class _FilterPills extends StatelessWidget {
  final FinishedTasksLoaded state;
  const _FilterPills( { required this.state } );

  @override
  Widget build( BuildContext context ) {
    return Padding(
      padding: const EdgeInsets.symmetric( horizontal: 12, vertical: 8 ),
      child: Wrap(
        spacing: 8,
        children: kFinishedStatuses.map( ( status ) {
          final face  = kFinishedStatusFaces[ status ]!;
          final count = state.result.countFor( status );
          final lit   = state.shown.contains( status );
          // null is "we do not know" — a failed fetch — and must not render as 0.
          final countLabel = count == null ? kFinishedUnmeasured : "$count";
          return FilterChip(
            key      : Key( "${TestKeys.finishedStatusPillPrefix}$status" ),
            selected : lit,
            tooltip  : face.description,
            // ⚠️ THE PILL'S EMOJI IS EXCLUDED FROM THE SPOKEN LABEL for the same
            // reason the row's glyph is: the status is already in the words beside
            // it, so TalkBack saying "white heavy check mark" is noise, not access.
            // `semanticsLabel` replaces the whole string for a screen reader while
            // the sighted label keeps its glyph.
            label    : Text(
              "${face.icon} ${face.label} ($countLabel)",
              semanticsLabel: "${face.label}, $countLabel",
            ),
            onSelected: ( _ ) => context
                .read<FinishedTasksBloc>()
                .add( FinishedTasksStatusToggled( status ) ),
          );
        } ).toList(),
      ),
    );
  }
}

/// The window control — carried, not just its default.
class _WindowControl extends StatelessWidget {
  final int days;
  const _WindowControl( { required this.days } );

  @override
  Widget build( BuildContext context ) {
    final bloc = context.read<FinishedTasksBloc>();
    return Padding(
      padding: const EdgeInsets.symmetric( horizontal: 12 ),
      child: Row(
        children: [
          Text( "Window", style: Theme.of( context ).textTheme.labelMedium ),
          Expanded(
            child: Slider(
              key       : const Key( TestKeys.finishedWindowSlider ),
              value     : days.toDouble(),
              min       : kFinishedWindowMinDays.toDouble(),
              max       : kFinishedWindowMaxDays.toDouble(),
              divisions : kFinishedWindowMaxDays - kFinishedWindowMinDays,
              label     : days == 1 ? "1 day" : "$days days",
              // Dragging previews; releasing refetches. One request per gesture
              // rather than one per frame.
              onChanged      : ( v ) => bloc.add( FinishedTasksWindowPreviewed( v.round() ) ),
              onChangeEnd    : ( v ) => bloc.add( FinishedTasksWindowChanged( v.round() ) ),
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              days == 1 ? "1 day" : "$days days",
              key      : const Key( TestKeys.finishedWindowLabel ),
              textAlign: TextAlign.end,
              style    : Theme.of( context ).textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// Says out loud that part of the window is missing, rather than rendering a failed
/// fetch as "nothing was closed".
class _PartialBanner extends StatelessWidget {
  final dynamic result;
  const _PartialBanner( { required this.result } );

  @override
  Widget build( BuildContext context ) {
    final missing = ( result.failures as Map ).keys
        .map( ( s ) => kFinishedStatusFaces[ s ]?.label ?? s )
        .join( ", " );
    return Container(
      key     : const Key( TestKeys.finishedPartialBanner ),
      width   : double.infinity,
      color   : Theme.of( context ).colorScheme.errorContainer,
      padding : const EdgeInsets.symmetric( horizontal: 12, vertical: 8 ),
      child   : Text(
        "Could not load $missing — those rows are missing from this list, not absent.",
        style: TextStyle( color: Theme.of( context ).colorScheme.onErrorContainer ),
      ),
    );
  }
}

class _RowList extends StatelessWidget {
  final List<FinishedTaskEvent> rows;
  const _RowList( { required this.rows } );

  @override
  Widget build( BuildContext context ) {
    if ( rows.isEmpty ) {
      return ListView(
        // Must stay scrollable, or pull-to-refresh cannot be started from an
        // empty pane — the one state a user most wants to refresh.
        physics  : const AlwaysScrollableScrollPhysics(),
        children : const [
          SizedBox( height: 64 ),
          Center(
            key   : Key( TestKeys.finishedEmptyState ),
            child : Text( "Nothing finished in this window." ),
          ),
        ],
      );
    }
    return ListView.builder(
      physics     : const AlwaysScrollableScrollPhysics(),
      itemCount   : rows.length,
      itemBuilder : ( context, i ) => FinishedTaskRow(
        event : rows[ i ],
        now   : DateTime.now(),
      ),
    );
  }
}

/// One finished-work row: **four cells**, and it is not the shared `TaskRow`.
///
/// 🔴 THE GLYPH IS A PREFIX INSIDE THE WHEN CELL AND NEVER A FIFTH COLUMN, and that
/// is load-bearing rather than cosmetic. In a done-only view every glyph is an
/// identical ✅ and the tempting move is to hide it until a second filter is lit —
/// rejected, because a grid that changes shape when you click a filter makes the
/// reader re-find every column, which costs more than one redundant character. A
/// prefix costs no horizontal space, so the layout holds across all seven filter
/// combinations and the row stays at four cells.
///
/// ⚠️ THE GLYPH IS HIDDEN FROM THE SCREEN READER, and that is access rather than
/// neglect: the status is already announced in words by the row's own semantic
/// label, so speaking the emoji as well is noise. `ExcludeSemantics` is the Flutter
/// spelling of the web's `aria-hidden`.
///
/// ⚠️ FOUR CELLS, TWO LINES — deliberately not four across. At 360 dp, four columns
/// plus a status prefix leave roughly 90 dp for the title, which truncates every row
/// in this fleet to the same `[LUPIN-MOBILE] Phase…` prefix. The cell COUNT is what
/// the source makes load-bearing (the shape must not change when a filter is lit);
/// the arrangement is ours, and it is stable across all seven combinations.
class FinishedTaskRow extends StatelessWidget {
  final FinishedTaskEvent event;
  final DateTime          now;

  const FinishedTaskRow( {
    super.key,
    required this.event,
    required this.now,
  } );

  @override
  Widget build( BuildContext context ) {
    final theme  = Theme.of( context );
    final status = event.status;
    final face   = kFinishedStatusFaces[ status ];
    final age    = relativeAge( event.ts, now );
    final who    = actorPersona( event.actor );
    final why    = ( event.reason == null || event.reason!.trim().isEmpty )
        ? kFinishedUnmeasured
        : event.reason!.trim();

    return Semantics(
      // The status reaches a screen reader HERE, in words, which is what lets the
      // glyph itself be excluded below.
      label: "${face?.label ?? status}, $age ago, by $who",
      child: Padding(
        padding: const EdgeInsets.symmetric( horizontal: 12, vertical: 10 ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── cell 1: WHEN, with the status glyph as its prefix ──
                SizedBox(
                  width: 62,
                  child: Row(
                    children: [
                      ExcludeSemantics(
                        child: Text(
                          face?.icon ?? "",
                          key: Key( "${TestKeys.finishedRowGlyphPrefix}${event.id}" ),
                        ),
                      ),
                      const SizedBox( width: 4 ),
                      Flexible(
                        child: Text(
                          age,
                          key      : Key( "${TestKeys.finishedRowWhenPrefix}${event.id}" ),
                          style    : theme.textTheme.bodySmall,
                          overflow : TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                // ── cell 2: TITLE, which gets the room ──
                Expanded(
                  child: Text(
                    event.title,
                    key      : Key( "${TestKeys.finishedRowTitlePrefix}${event.id}" ),
                    style    : theme.textTheme.bodyMedium,
                    maxLines : 2,
                    overflow : TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox( width: 8 ),
                // ── cell 3: WHO ──
                SizedBox(
                  width: 76,
                  child: Text(
                    who,
                    key      : Key( "${TestKeys.finishedRowWhoPrefix}${event.id}" ),
                    style    : theme.textTheme.bodySmall,
                    textAlign: TextAlign.end,
                    overflow : TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox( height: 2 ),
            // ── cell 4: WHY ──
            Padding(
              padding: const EdgeInsets.only( left: 62 ),
              child: Text(
                why,
                key      : Key( "${TestKeys.finishedRowWhyPrefix}${event.id}" ),
                style    : theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines : 2,
                overflow : TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String        message;
  final VoidCallback  onRetry;
  const _ErrorView( { required this.message, required this.onRetry } );

  @override
  Widget build( BuildContext context ) {
    return Center(
      key: const Key( TestKeys.finishedErrorView ),
      child: Padding(
        padding: const EdgeInsets.all( 24 ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text( message, textAlign: TextAlign.center ),
            const SizedBox( height: 12 ),
            FilledButton( onPressed: onRetry, child: const Text( "Retry" ) ),
          ],
        ),
      ),
    );
  }
}
