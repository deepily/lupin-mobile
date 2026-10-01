import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/testing/test_keys.dart';
import '../data/finished_tasks_models.dart';
import '../domain/finished_tasks_bloc.dart';
import '../domain/finished_tasks_event.dart';
import '../domain/finished_tasks_state.dart';

/// The Finished Tasks pane: what just got done, by whom, and why it closed.
///
/// The pane builds its own row and must keep doing so.
/// Its rows are `task_events`, which carry no priority, blocked state, accountable
/// manager or actions, so the shared `TaskRow` would render fields this data lacks.
/// The rule against a row of its own applies to the Holding Area, not to this pane.
/// The widget test asserts the absence of `TaskRow`, so unifying fails at the refactor.
class FinishedTasksScreen extends StatefulWidget {
  /// Creates the screen.
  const FinishedTasksScreen( { super.key } );

  @override
  State<FinishedTasksScreen> createState() => _FinishedTasksScreenState();
}

class _FinishedTasksScreenState extends State<FinishedTasksScreen> {
  /// The bloc, held rather than looked up in `dispose()`.
  ///
  /// By the time `dispose` runs, the element is being torn down and `context.read` can
  /// throw, which would skip the rest of dispose.
  /// The timer would then outlive the pane, polling a screen nobody is looking at.
  late final FinishedTasksBloc _bloc;

  @override
  void initState() {
    super.initState();
    _bloc = context.read<FinishedTasksBloc>()..startPolling();
    // `onPaneVisible()` is the first load, and no second trigger sits beside it.
    // The mixin refreshes immediately when a pane appears, so a `FinishedTasksRequested`
    // here as well would issue two window fetches, six HTTP calls, and
    // `finished_tasks_first_load_test.dart` asserts exactly one.
    // The pane still asks for its own data on mount: `FinishedTasksInitial` renders the
    // spinner until the answer lands, and a failed first load paints the error view,
    // because the poll path stays silent only once there are rows to keep.
    // See `FinishedTasksBloc._onPolled`.
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
          // A refresh button, not only pull-to-refresh: `RefreshIndicator` has no semantic
          // action a screen reader can invoke, and TalkBack does not pass the pull drag
          // through, so without this button that user cannot refresh the pane.
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
/// A pill's count does not depend on whether it is lit.
/// An unlit status withholds its rows but still shows its count.
/// The user then learns that rows were closed as won't-fix without lighting the pill.
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
            // The emoji is left out of the spoken label because the status is already in
            // the words beside it; `semanticsLabel` replaces the string for a screen
            // reader while the sighted label keeps its glyph.
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

/// The window slider and its day label.
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
              // Dragging previews; releasing refetches, so one request per gesture.
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

/// Says part of the window is missing, so a failed fetch is not read as "nothing closed".
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

/// The list of finished rows, or the empty state.
class _RowList extends StatelessWidget {
  final List<FinishedTaskEvent> rows;
  const _RowList( { required this.rows } );

  @override
  Widget build( BuildContext context ) {
    if ( rows.isEmpty ) {
      return ListView(
        // Must stay scrollable, or pull-to-refresh cannot start from an empty pane.
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

/// One finished-work row of four cells; it is not the shared `TaskRow`.
///
/// The status glyph is a prefix inside the When cell and never a fifth column.
/// Hiding it in a done-only view would make the grid change shape when a filter is lit.
/// A prefix costs no horizontal space, so the layout holds across all seven filter
/// combinations.
///
/// The glyph is hidden from the screen reader because the row's semantic label already
/// announces the status in words.
///
/// The four cells sit on two lines, not four across.
/// At 360 dp, four columns leave roughly 90 dp for the title, which would truncate
/// every row to the same `[LUPIN-MOBILE] Phase…` prefix.
class FinishedTaskRow extends StatelessWidget {
  /// The event to render.
  final FinishedTaskEvent event;
  /// The instant ages are measured against.
  final DateTime          now;

  /// Creates a row for [event], aged against [now].
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
      // The status reaches a screen reader here, in words, which is what lets the glyph
      // be excluded below.
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

/// The full-pane error with a Retry button.
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
