import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/testing/test_keys.dart';
import '../domain/transcript_stream_bloc.dart';
import 'transcript_block_view.dart';

/// The Live Console — one Claude Code seat's transcript as it is written, read-only
/// (ruling Q9).
///
/// 🔴 THE BLOC IS CREATED BY THIS ROUTE AND DIES WITH IT (C1). Not an app-root
/// `ServiceLocator` singleton like every other bloc in this app, and that asymmetry is the
/// mechanism rather than a preference: an app-root console bloc keeps its server-side watch
/// open after the operator walks away, and the obvious test — *"the console stops when you
/// leave it"* — PASSES ANYWAY, because nothing on screen is asking. C5.11's negative control
/// is to register it app-root and watch the test go red.
class LiveConsoleScreen extends StatelessWidget {
  /// The seat's full `stable_session_id` — §3's `cc_session_id`.
  ///
  /// ⚠️ THE FULL ID, NEVER THE 8-CHARACTER FORM. The roster join and the stream both key on
  /// this exact string at this exact width (§3), which is why the fleet row is the only entry
  /// point in v1 — it is the only surface that has it (C-5).
  final String ccSessionId;

  /// What to call the seat on screen.
  final String whoLabel;

  /// How the route builds its bloc.
  ///
  /// REQUIRED rather than optional-with-a-fallback, following `FleetStatusScreen`: an
  /// optional factory needs a `!` at the use site, which is a crash waiting for the first
  /// caller who forgets it.
  final TranscriptStreamBloc Function( BuildContext ) blocFactory;

  const LiveConsoleScreen( {
    super.key,
    required this.ccSessionId,
    required this.whoLabel,
    required this.blocFactory,
  } );

  @override
  Widget build( BuildContext context ) {
    return BlocProvider<TranscriptStreamBloc>(
      // `create`, never `.value` — see the class docstring.
      create : blocFactory,
      child  : _ConsoleView( ccSessionId: ccSessionId, whoLabel: whoLabel ),
    );
  }
}

class _ConsoleView extends StatefulWidget {
  final String ccSessionId;
  final String whoLabel;

  const _ConsoleView( { required this.ccSessionId, required this.whoLabel } );

  @override
  State<_ConsoleView> createState() => _ConsoleViewState();
}

class _ConsoleViewState extends State<_ConsoleView> {
  /// 🔴 HELD AS A FIELD BECAUSE `dispose()` CANNOT LOOK UP AN ANCESTOR, and the first cut of
  /// `FleetStatusScreen` learned that the expensive way: `context.read<…>()` inside
  /// `dispose()` throws *"Looking up a deactivated widget's ancestor is unsafe"*, the throw
  /// meant `onPaneHidden()` never ran, and the poll timer survived the route. The framework
  /// names the remedy in the error text — save the reference in `didChangeDependencies()`.
  late final TranscriptStreamBloc _bloc;

  final ScrollController _scroll = ScrollController();

  /// True while the view is pinned to the live end.
  bool _following = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bloc = context.read<TranscriptStreamBloc>();
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener( _onScroll );

    // Deferred to the first frame: `initState` runs before `didChangeDependencies`, so the
    // bloc is not resolved yet.
    WidgetsBinding.instance.addPostFrameCallback( ( _ ) {
      if ( !mounted ) return;
      _bloc.start();
      // The route says the screen is on view. The mixin's hook then runs the catch-up and
      // the watch — and runs it again on every return from the background.
      _bloc.onPaneVisible();
    } );
  }

  @override
  void dispose() {
    // The SAVED reference. This sends `cc_transcript_unwatch` and cancels the in-flight
    // fetch rather than letting either outlive the route.
    _bloc.onPaneHidden();
    _scroll.removeListener( _onScroll );
    _scroll.dispose();
    super.dispose();
  }

  /// 🔴 THE LIVE END IS `minScrollExtent` AND IT IS AT THE **BOTTOM**. OSQ-9 was ruled
  /// Option B by Rick on 2026-09-27 — newest at the bottom, terminal convention — which
  /// makes this list the repo's FIRST `reverse: true`. He chose it knowing it departs from
  /// ruling 3 (newest at the top) that every other list in this app follows, so the console
  /// is a deliberate exception rather than an inconsistency.
  ///
  /// ⚠️ `reverse: true` INVERTS THE MEANING OF THE EXTENTS, NOT JUST THE PAINT ORDER.
  /// `minScrollExtent` is the visual BOTTOM here and `maxScrollExtent` the top, which is why
  /// "am I following?" is a test against the minimum and "Load earlier" sits at the maximum.
  void _onScroll() {
    if ( !_scroll.hasClients ) return;

    final atLive = _scroll.position.pixels <=
        _scroll.position.minScrollExtent + _followSlack;

    if ( atLive != _following ) setState( () => _following = atLive );
  }

  /// A few pixels of slack, so a one-pixel overscroll does not read as "scrolled away".
  static const double _followSlack = 24.0;

  /// 🔴 `jumpTo`, NOT `animateTo` (`quick_ask_screen.dart:569`: "an animation is a race the
  /// user can win"). A fling already in flight cancels an animation and leaves the view off
  /// the live end again — which is the bug, not the fix. C5.4 asserts the pill returns via
  /// `jumpTo`.
  void _jumpToLive() {
    if ( !_scroll.hasClients ) return;
    _scroll.position.jumpTo( _scroll.position.minScrollExtent );
    setState( () => _following = true );
  }

  @override
  Widget build( BuildContext context ) {
    return Scaffold(
      key    : const Key( TestKeys.liveConsoleScreen ),
      appBar : AppBar(
        title : Text( "Console — ${ widget.whoLabel }" ),
      ),
      // 🔴 NO `bottomNavigationBar`, NO INPUT, NO FAB, NO REPLY ACTION. Ruling Q8: nothing
      // flows from client to seat, and the only client verbs are watch and unwatch. C5.5
      // asserts the ABSENCE — no text field, no send button — which is a claim about the
      // whole subtree and is why it is worth stating here as well as testing.
      body   : BlocBuilder<TranscriptStreamBloc, TranscriptViewState>(
        builder: ( context, state ) {
          if ( state.refused )     return _refusedView( context, state );
          if ( state.loading && state.blocks.isEmpty ) {
            return const Center(
              child: CircularProgressIndicator( key: Key( TestKeys.liveConsoleSpinner ) ),
            );
          }
          if ( state.blocks.isEmpty && state.error != null ) {
            return _errorView( context, state );
          }
          return _list( context, state );
        },
      ),
    );
  }

  Widget _list( BuildContext context, TranscriptViewState state ) {
    // The list is `reverse: true`, so index 0 is the NEWEST and sits at the bottom. The
    // bloc holds blocks oldest-first, so the view index maps backwards.
    final blocks = state.blocks;
    final count  = blocks.length + ( _showLoadEarlier( state ) ? 1 : 0 );

    return Stack(
      children: [
        ListView.builder(
          key        : const Key( TestKeys.liveConsoleList ),
          controller : _scroll,
          reverse    : true,
          itemCount  : count,
          itemBuilder: ( context, i ) {
            // The extra tail item — which, under `reverse: true`, is at the TOP, the far end
            // from live. That is where "Load earlier" belongs (C-7).
            if ( i >= blocks.length ) return _loadEarlierButton( state );

            final index = blocks.length - 1 - i;
            final block = blocks[ index ];

            return TranscriptBlockView(
              // 🔴 KEYED ON THE BLOCK'S OFFSET, AND **NOT** ON `truncated`. My first version
              // was `ValueKey( "block-$index-${ block.truncated }" )`, which looked careful
              // and was a bug: filling a truncated block flips `truncated` to false, so the
              // key CHANGED, Flutter built a fresh element, `initState` re-collapsed it —
              // and the text the operator had just waited for a REST round trip to see was
              // hidden the frame it arrived. Caught by C5.19 going red on the fetched string.
              //
              // ⚠️ THE OFFSET RATHER THAN THE INDEX, because the ring evicts oldest-first and
              // indices shift under it. An index key would carry one block's expanded state
              // onto whatever block later occupies that slot. The offset is stable for the
              // life of the epoch; a block without one falls back to the index, which is the
              // best available and is at least stable while nothing is evicted.
              key         : ValueKey( "block-${ block.offset ?? 'i$index' }" ),
              block       : block,
              onFetchFull : block.truncated
                  ? () => context.read<TranscriptStreamBloc>().expandTruncated( index )
                  : null,
            );
          },
        ),
        if ( !_following )
          Positioned(
            // Bottom, because that is where live is.
            bottom : 16,
            right  : 16,
            child  : FloatingActionButton.small(
              key       : const Key( TestKeys.liveConsoleJumpToLive ),
              onPressed : _jumpToLive,
              tooltip   : "Jump to live",
              child     : const Icon( Icons.arrow_downward ),
            ),
          ),
        if ( state.error != null )
          Positioned(
            top   : 0,
            left  : 0,
            right : 0,
            child : Material(
              color : Theme.of( context ).colorScheme.errorContainer,
              child : Padding(
                padding : const EdgeInsets.all( 8 ),
                child   : Text(
                  state.error!,
                  key       : const Key( TestKeys.liveConsoleError ),
                  textAlign : TextAlign.center,
                  style     : Theme.of( context ).textTheme.bodySmall,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Visible only while there is more of this epoch to fetch (C-7).
  bool _showLoadEarlier( TranscriptViewState state ) =>
      !state.atEpochStart && state.oldestOffset != null && state.oldestOffset! > 0;

  Widget _loadEarlierButton( TranscriptViewState state ) => Padding(
    padding : const EdgeInsets.symmetric( vertical: 8 ),
    child   : Center(
      child: state.loadingEarlier
          ? const SizedBox(
              height : 24,
              width  : 24,
              child  : CircularProgressIndicator( strokeWidth: 2 ),
            )
          : TextButton.icon(
              key       : const Key( TestKeys.liveConsoleLoadEarlier ),
              icon      : const Icon( Icons.expand_less, size: 18 ),
              label    : const Text( "Load earlier" ),
              onPressed : () => context.read<TranscriptStreamBloc>().loadEarlier(),
            ),
    ),
  );

  /// 🔴 A REFUSED WATCH IS FINAL, AND THIS SCREEN IS WHAT THAT LOOKS LIKE (F-Clayton-C6).
  /// §5: "it shows a static 'Console not available for this session' message with the
  /// server's reason if one is given, keeps no buffer, sends no further watch, **does not
  /// retry**, and offers only Back. No spinner, no retry loop." So there is no Retry button
  /// here — deliberately, and C5.21's negative control is a build that retries on resume or
  /// on reconnect.
  Widget _refusedView( BuildContext context, TranscriptViewState state ) {
    final theme = Theme.of( context );

    return Center(
      key   : const Key( TestKeys.liveConsoleRefused ),
      child : Padding(
        padding : const EdgeInsets.all( 24 ),
        child   : Column(
          mainAxisSize : MainAxisSize.min,
          children     : [
            Icon( Icons.lock_outline, size: 40, color: theme.hintColor ),
            const SizedBox( height: 12 ),
            const Text( "Console not available for this session" ),
            if ( state.refusedReason != null ) ...[
              const SizedBox( height: 6 ),
              Text(
                state.refusedReason!,
                key       : const Key( TestKeys.liveConsoleRefusedReason ),
                textAlign : TextAlign.center,
                style     : theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox( height: 16 ),
            TextButton(
              key       : const Key( TestKeys.liveConsoleBack ),
              onPressed : () => Navigator.of( context ).maybePop(),
              child     : const Text( "Back" ),
            ),
          ],
        ),
      ),
    );
  }

  /// A retryable failure with nothing yet to show. Distinct from a refusal: the console keeps
  /// trying on the next lifecycle event, so this says so rather than offering a dead button.
  Widget _errorView( BuildContext context, TranscriptViewState state ) => Center(
    child: Padding(
      padding : const EdgeInsets.all( 24 ),
      child   : Column(
        mainAxisSize : MainAxisSize.min,
        children     : [
          const Icon( Icons.signal_wifi_off, size: 40 ),
          const SizedBox( height: 12 ),
          const Text( "Could not read the console" ),
          const SizedBox( height: 6 ),
          Text(
            state.error!,
            key       : const Key( TestKeys.liveConsoleError ),
            textAlign : TextAlign.center,
            style     : Theme.of( context ).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}
