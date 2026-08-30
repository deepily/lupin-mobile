import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/service_locator.dart';
import '../../../core/testing/test_keys.dart';
import '../../../services/notification_audio/notification_preferences.dart';
import '../../../services/notification_filter/notification_stop_list.dart';
import '../../../services/notification_filter/progress_group_collapse.dart';
import '../../../services/tts/speech_intent.dart';
import '../../../shared/widgets/prompt_bodies.dart';
import '../../notifications/presentation/interactive_prompt_sheet.dart';
import '../../notifications/presentation/message_stamp.dart';
import '../../notifications/presentation/persona_badge.dart';
import '../domain/focus_chat_bloc.dart';
import '../domain/focus_chat_event.dart';
import '../domain/focus_chat_state.dart';
import 'tts_fraction_bar.dart';

/// The chat pane half of the focus surface (S3 §3.1): header (badge +
/// sender name), the focused sender's last-7 window newest-at-bottom,
/// inline prompts on the newest UNANSWERED ask (buried-ask rule via S2's
/// `pendingPromptFor`, F-S3-S2-1), and the cold-start/hydration states
/// (F-S3-S2-3 — empty-state hint, loading spinner, error retry banner).
///
/// All inline responses dispatch via `FocusRespondRequested` with an
/// explicit typed `FocusPromptContext` (F-S3-2). Batch open-ended asks —
/// and multi-select multiple-choice (same Map/List reasoning, implementer
/// call S3 §8) — render a fallback affordance that opens the legacy
/// `InteractivePromptSheet` (F-S3-S2-2(d)).
class FocusChatPane extends StatefulWidget {
  /// Retry seam: the error banner re-dispatches `FocusColdStartRequested`,
  /// which needs the authenticated email (provided by the screen).
  final String? userEmail;
  /// Filter prefs (collapse toggle). Tests inject; production resolves from
  /// the locator when registered; null ⇒ collapse ON (browser parity).
  final NotificationStopList? stopList;
  /// Audio prefs for the pinned TTS-fraction slider. Tests inject; production
  /// resolves from the locator; null => no slider rendered.
  final NotificationPreferences? prefs;

  const FocusChatPane( { super.key, this.userEmail, this.stopList, this.prefs } );

  @override
  State<FocusChatPane> createState() => _FocusChatPaneState();
}

class _FocusChatPaneState extends State<FocusChatPane> {
  NotificationStopList?    _stopList;
  NotificationPreferences? _prefs;
  String? get userEmail => widget.userEmail;

  @override
  void initState() {
    super.initState();
    _prefs = widget.prefs ??
        ( ServiceLocator.isRegistered<NotificationPreferences>()
            ? ServiceLocator.get<NotificationPreferences>()
            : null );
    _stopList = widget.stopList ??
        ( ServiceLocator.isRegistered<NotificationStopList>()
            ? ServiceLocator.get<NotificationStopList>()
            : null );
    _stopList?.addListener( _onPrefsChanged );
  }

  @override
  void dispose() {
    _stopList?.removeListener( _onPrefsChanged );
    super.dispose();
  }

  void _onPrefsChanged() {
    if ( mounted ) setState( () {} );
  }

  /// A pending ask is never buried inside a collapsed group.
  static String? _groupKey( FocusMessage m ) =>
      m.item.responseRequested ? null : m.item.progressGroupId;

  @override
  Widget build( BuildContext context ) {
    return BlocBuilder<FocusChatBloc, FocusChatState>(
      builder: ( context, state ) {
        return Column(
          key: const Key( TestKeys.focusChatPane ),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Pinned ABOVE everything else in the pane -- survives sender
            // switches, loading and error states (Rick 2026-08-21).
            if ( _prefs != null ) TtsFractionBar( prefs: _prefs! ),
            if ( state.hydration == FocusHydration.error )
              _RetryBanner( userEmail: userEmail ),
            Expanded( child: _body( context, state ) ),
          ],
        );
      },
    );
  }

  Widget _body( BuildContext context, FocusChatState state ) {
    if ( state.hydration == FocusHydration.loading ) {
      return const Center( child: CircularProgressIndicator() );
    }
    final focused = state.focusedSender;
    if ( focused == null ) {
      // Cold-start empty state (Q4-LITERAL — no auto-focus, ever).
      return const Center(
        child: Padding(
          padding : EdgeInsets.all( 24 ),
          child   : Text(
            'Tap a session badge to focus its conversation.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final stored  = state.windows[ focused ] ?? const <FocusMessage>[];
    final pending = state.pendingPromptFor( focused );
    final persona = state.personasBySender[ focused ];

    // Stop-list RENDER lens (2026-08-21, Rick: "Done: Bash is checked yet
    // still shows"): ingest suppression only catches NEW arrivals, so a
    // pattern checked after a bubble landed left it on screen. Apply the
    // same predicate here too — the window is retained (hide-not-delete),
    // so unchecking reveals again instantly; the pane already re-renders on
    // any stop-list change via [_onPrefsChanged]. User replies never hide.
    //
    // 🔴 AC-S4.15 — AND NEITHER DOES AN ACTIONABLE QUESTION. The bloc already
    // exempts one at ingest ([_onInbound]: `rule != null && !actionable`), on
    // Rick's AC-S3.8(2) ruling that such an item is *shown, muted, marked,
    // playback available*. This lens is the SECOND enforcement point of that
    // one rule and it had drifted: it exempted only user replies, so a
    // question the bloc deliberately kept was filtered straight back out.
    // The user was then muted AND marked AND NOT SHOWN — the one combination
    // the ruling forbids, because they are being asked to act on something
    // they cannot see, while the server blocks on a reply they cannot send.
    //
    // Measured by `test/service_integration/suppression_seam_test.dart` on its
    // first run: gate 1 muted the question, the bloc stored it with its
    // suppression retained, and the pane rendered neither the notice nor the
    // answer controls — while AC-S3.7's and AC-S4.14's own tests stayed GREEN.
    //
    // [isActionableQuestion] is RE-USED, never re-implemented: one predicate,
    // two enforcement points. A second copy here is exactly how the first
    // divergence happened.
    final sl      = _stopList;
    final window  = sl == null
        ? stored
        : stored.where( ( m ) =>
            m.item.type == 'user_initiated_message' ||
            !sl.matches( m.item.message ) ||
            isActionableQuestion(
              responseRequested : m.item.responseRequested,
              senderId          : m.item.senderId,
              jobId             : m.item.jobId,
            ) ).toList();
    final hidden  = ( state.hiddenCountBySender[ focused ] ?? 0 ) + ( stored.length - window.length );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header: badge + sender name.
        Padding(
          padding: const EdgeInsets.symmetric( horizontal: 12, vertical: 8 ),
          child: Row(
            children: [
              if ( persona != null )
                PersonaBadge( persona: persona, senderId: focused, diameter: 28 ),
              if ( persona != null ) const SizedBox( width: 8 ),
              Expanded(
                child: Text(
                  focused,
                  style    : Theme.of( context ).textTheme.titleMedium,
                  overflow : TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const Divider( height: 1 ),
        if ( hidden > 0 )
          Padding(
            key     : const Key( TestKeys.focusHiddenCaption ),
            padding : const EdgeInsets.fromLTRB( 12, 4, 12, 0 ),
            child   : Text(
              '$hidden hidden by your stop-list',
              style: Theme.of( context ).textTheme.labelSmall?.copyWith(
                color: Theme.of( context ).colorScheme.outline ),
            ),
          ),
        Expanded(
          child: window.isEmpty
              ? Center( child: Text( stored.isEmpty
                  ? 'No messages yet in this window.'
                  : 'Everything here is hidden by your stop-list.' ) )
              : Builder( builder: ( context ) {
                  // NEWEST AT THE TOP (Rick 2026-08-21): the window is stored
                  // oldest→newest; group first (runs are contiguous either
                  // way), then render the groups reversed. Inside an expanded
                  // group the children are newest-first too.
                  final groups = collapseByProgressGroup<FocusMessage>(
                    window, _groupKey, enabled: _stopList?.collapseGroups ?? true )
                    .reversed.toList( growable: false );
                  return ListView.builder(
                    padding     : const EdgeInsets.all( 8 ),
                    itemCount   : groups.length,
                    itemBuilder : ( context, i ) {
                      final g = groups[ i ];
                      if ( !g.isCollapsed ) {
                        final m = g.items.single;
                        return _MessageBubble(
                          msg            : m,
                          senderId       : focused,
                          isPendingPrompt: pending?.item.id == m.item.id,
                        );
                      }
                      return _CollapsedGroup(
                        key      : Key( '${TestKeys.focusGroupPrefix}${g.key}-${g.latest.item.id}' ),
                        count    : g.count,
                        summary  : _MessageBubble( msg: g.latest, senderId: focused, isPendingPrompt: false ),
                        children : [ for ( final m in g.items.reversed )
                          _MessageBubble( msg: m, senderId: focused, isPendingPrompt: false ) ],
                      );
                    },
                  );
                } ),
        ),
      ],
    );
  }
}

class _RetryBanner extends StatelessWidget {
  final String? userEmail;
  const _RetryBanner( { required this.userEmail } );

  @override
  Widget build( BuildContext context ) {
    return Material(
      color: Theme.of( context ).colorScheme.errorContainer,
      child: InkWell(
        key   : const Key( TestKeys.focusRetryBanner ),
        onTap : () {
          final email = userEmail;
          if ( email != null ) {
            context
                .read<FocusChatBloc>()
                .add( FocusColdStartRequested( userEmail: email ) );
          }
        },
        child: const Padding(
          padding : EdgeInsets.all( 12 ),
          child   : Row(
            children: [
              Icon( Icons.refresh, size: 18 ),
              SizedBox( width: 8 ),
              Expanded( child: Text( 'Something went wrong — tap to retry.' ) ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final FocusMessage msg;
  final String       senderId;
  final bool         isPendingPrompt;

  /// AC-S4.14's speak-anyway hook. Reaching the orchestrator's
  /// `speakAnyway( TtsSuppression )` needs the ORIGINAL suppression object,
  /// which is emitted at INGEST — long before this widget mounts — and is not
  /// retained anywhere today. So the host injects the handler rather than this
  /// widget reconstructing a `TtsSuppression`, which would guess `verbatim`
  /// and `sender` and amount to a second source of truth for a stream that
  /// already owns them.

  const _MessageBubble( {
    required this.msg,
    required this.senderId,
    required this.isPendingPrompt,
  } );

  static const _priorityAccent = {
    'low'    : Colors.blueGrey,
    'medium' : Colors.blue,
    'high'   : Colors.orange,
    'urgent' : Colors.red,
  };

  bool get _isUserReply => msg.item.type == 'user_initiated_message';

  @override
  Widget build( BuildContext context ) {
    final theme  = Theme.of( context );
    final accent = _priorityAccent[ msg.item.priority ] ?? Colors.blueGrey;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if ( msg.item.title != null && msg.item.title!.isNotEmpty )
          Text( msg.item.title!, style: theme.textTheme.labelLarge ),
        Text( msg.item.message ),
        // AC-S4.14 — a question the stop-list suppressed says so, names the
        // rule, and offers speak-anyway. It renders HERE, above the prompt
        // zone, so the normal answer controls below it stay intact: the user
        // can answer silently, which is the whole point. Putting this notice
        // in an answer card instead would tell the user something was muted
        // and give them no way to act on it, while the server stays blocked.
        if ( msg.suppressedRule != null )
          _SuppressedNotice( msg: msg ),
        if ( msg.item.responseRequested ) _promptZone( context ),
        const SizedBox( height: 2 ),
        MessageStamp( timestamp: msg.item.timestamp, id: msg.item.id ),   // lower-left
      ],
    );

    return Align(
      alignment: _isUserReply ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin     : const EdgeInsets.symmetric( vertical: 4 ),
        constraints: const BoxConstraints( maxWidth: 320 ),
        clipBehavior: Clip.antiAlias,
        decoration : BoxDecoration(
          color: _isUserReply
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular( 10 ),
        ),
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Priority accent bar (Claude-sent bubbles only).
              if ( !_isUserReply ) Container( width: 3, color: accent ),
              Flexible(
                child: Padding(
                  padding : const EdgeInsets.all( 10 ),
                  child   : content,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _promptZone( BuildContext context ) {

    if ( msg.answered ) {
      return const Padding(
        padding : EdgeInsets.only( top: 6 ),
        child   : Chip(
          visualDensity : VisualDensity.compact,
          avatar        : Icon( Icons.check, size: 14 ),
          label         : Text( 'answered' ),
        ),
      );
    }
    if ( !isPendingPrompt ) {
      // Unanswered but NOT the newest unanswered ask — buttons attach only
      // via pendingPromptFor (one ask actionable at a time, F-S3-S2-1).
      return const SizedBox.shrink();
    }

    final bloc = context.read<FocusChatBloc>();
    void respond( String text ) {
      bloc.add( FocusRespondRequested(
        senderId      : senderId,
        text          : text,
        promptContext : FocusPromptContext(
          notificationId : msg.item.id,
          promptType     : msg.item.responseType,
        ),
      ) );
    }

    final type  = msg.item.responseType;
    final opts  = msg.item.responseOptions;
    final multi = opts?[ 'multi_select' ] == true;
    // BACKFILLED multiple_choice asks carry NULL options — the 19-field
    // conversation wire never emits response_options (Phase-0 capture;
    // F-S2-IMPL-2 heads-up). Chips can only render from a live payload.
    final optionsRenderable = opts?[ 'options' ] is List;
    // 🔴 AC-S4.10b delta 1 / AC-S4.5: a CANONICAL `ask_multiple_choice`
    // payload nests its questions under `response_options.questions[]`, so
    // `optionsRenderable` was false for it and every canonical ask fell
    // through to the "Answer in full view…" fallback below. It renders
    // inline now, through the same promoted body the sheet uses.
    final nestedAll = ( opts?[ 'questions' ] as List? )?.cast<dynamic>() ?? const [];
    // SCOPED TO multiple_choice ON PURPOSE. Delta 1 is about the canonical
    // `ask_multiple_choice` payload; `open_ended_batch` keeps its existing
    // route to the legacy sheet. Letting the inline path swallow batch asks
    // too would be a FOURTH behavior change on this surface — a scope
    // escape under AC-S4.10b, and the existing batch-fallback test in
    // focus_mode_screen_test.dart catches it, which is what it is for.
    final nested = type == 'multiple_choice' ? nestedAll : const [];

    if ( nested.isEmpty &&
        ( type == 'open_ended_batch' ||
        ( type == 'multiple_choice' && ( multi || !optionsRenderable ) ) ) ) {
      // Map/List-valued asks stay String-free on the focus path, and
      // option-less (backfilled) choice asks have nothing to chip: fallback
      // affordance → legacy sheet (F-S3-S2-2(d); multi-select + null-options
      // routing per the S3 §8 implementer calls).
      return Padding(
        padding : const EdgeInsets.only( top: 6 ),
        child   : OutlinedButton.icon(
          key       : Key( '${TestKeys.focusBatchFallbackPrefix}${msg.item.id}' ),
          icon      : const Icon( Icons.open_in_full, size: 16 ),
          label     : const Text( 'Answer in full view…' ),
          onPressed : () => InteractivePromptSheet.show(
            context        : context,
            notificationId : msg.item.id,
            responseType   : type ?? 'open_ended',
            options        : msg.item.responseOptions,
          ),
        ),
      );
    }

    Widget body;
    if ( nested.isNotEmpty ) {
      // The server parser wants {"answers": {header: value}}; the body
      // stays door-agnostic and this host wraps (AC-S4.11).
      return Padding(
        padding : const EdgeInsets.only( top: 8 ),
        child   : MultiQuestionPromptBody(
          questions : nested,
          onRespond : ( v ) => respond( jsonEncode( { 'answers': v } ) ),
        ),
      );
    }
    switch ( type ) {
      case 'yes_no':
        body = YesNoPromptBody( onRespond: respond );
        break;
      case 'multiple_choice':
        body = MultipleChoicePromptBody(
          options   : ( msg.item.responseOptions?[ 'options' ] as List? )
                  ?.cast<dynamic>() ??
              const [],
          multi     : false,
          // Single-select value is always a String (see prompt_bodies.dart
          // docstring) — safe on the String-typed focus path.
          onRespond : ( v ) => respond( v.toString() ),
        );
        break;
      case 'open_ended':
      default:
        body = OpenEndedPromptBody( onRespond: respond );
    }
    return Padding(
      padding : const EdgeInsets.only( top: 8 ),
      child   : body,
    );
  }
}

/// One expandable row standing in for a burst of same-progress-group
/// messages (plan 2026.08.21 §4): the LATEST message as the summary, a
/// ×N badge, tap to expand/collapse in place. Render-only state.
class _CollapsedGroup extends StatefulWidget {
  final int          count;
  final Widget       summary;
  final List<Widget> children;
  const _CollapsedGroup( { super.key, required this.count, required this.summary, required this.children } );

  @override
  State<_CollapsedGroup> createState() => _CollapsedGroupState();
}

class _CollapsedGroupState extends State<_CollapsedGroup> {
  bool _expanded = false;

  @override
  Widget build( BuildContext context ) {
    final theme = Theme.of( context );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key   : Key( '${TestKeys.focusGroupTogglePrefix}${widget.key.toString()}' ),
          onTap : () => setState( () => _expanded = !_expanded ),
          child : Row(
            children: [
              Expanded( child: _expanded ? const SizedBox.shrink() : widget.summary ),
              Padding(
                padding: const EdgeInsets.symmetric( horizontal: 8 ),
                child: Chip(
                  visualDensity : VisualDensity.compact,
                  avatar        : Icon( _expanded ? Icons.unfold_less : Icons.unfold_more, size: 14 ),
                  label         : Text( '×${widget.count}', style: theme.textTheme.labelSmall ),
                ),
              ),
            ],
          ),
        ),
        if ( _expanded ) ...widget.children,
      ],
    );
  }
}

/// AC-S4.14 — the suppressed question's notice.
///
/// 🔴 Rick's OSQ3 ruling: the stop-list HOLDS. `verbatim` bypasses gates 2 and
/// 3 only, and a pattern the user typed is not overridden by a flag. But **a
/// silently dropped question is indistinguishable from a hang** — the user
/// asked for nothing, hears nothing, and something on the server is blocked
/// waiting for them. So the suppression is made VISIBLE instead: the text is
/// always on screen, the matching rule is named, and one tap speaks it anyway.
///
/// Rick's own framing lowers the stakes rather than raising them — his
/// stop-list exists to stop repetitive event chatter rendering in the focus
/// bar, so an overlap with a deliberately-asked question is *"astronomically
/// unlikely"*. This is required for correctness and expected to fire
/// approximately never. Cheap and correct beats thorough here.
class _SuppressedNotice extends StatelessWidget {
  final FocusMessage msg;

  /// Supplied by the host. NULL means no handler is wired yet, and the
  /// speak-anyway affordance is then NOT rendered — a button that does
  /// nothing is worse than no button, because it tells the user the
  /// suppression is reversible and then is not.

  const _SuppressedNotice( { required this.msg } );

  @override
  Widget build( BuildContext context ) {
    final scheme = Theme.of( context ).colorScheme;
    final rule   = msg.suppressedRule ?? '';

    return Padding(
      key     : const Key( TestKeys.promptSuppressedNotice ),
      padding : const EdgeInsets.only( top: 6 ),
      child   : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize      : MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon( Icons.volume_off, size: 14, color: scheme.outline ),
              const SizedBox( width: 6 ),
              Flexible(
                child: Text(
                  key   : const Key( TestKeys.promptSuppressedRule ),
                  'Not spoken — matches your stop-list rule "$rule"',
                  style : TextStyle( fontSize: 11, color: scheme.outline ),
                ),
              ),
            ],
          ),
          // Offered only when the ORIGINAL suppression was retained — the
          // object gate 1 produced, handed straight back, so what plays is
          // what was refused rather than a reconstruction guessing `verbatim`
          // and `sender`.
          if ( msg.suppression != null )
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key       : const Key( TestKeys.promptSpeakAnyway ),
                icon      : const Icon( Icons.volume_up, size: 16 ),
                label     : const Text( 'Speak anyway' ),
                style     : TextButton.styleFrom(
                  padding       : const EdgeInsets.symmetric( horizontal: 8 ),
                  visualDensity : VisualDensity.compact,
                  tapTargetSize : MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed : () => context.read<FocusChatBloc>()
                    .add( FocusSpeakAnywayRequested( msg.item.id ) ),
              ),
            ),
        ],
      ),
    );
  }
}
