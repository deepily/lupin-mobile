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
import '../../docs/data/doc_repository.dart';
import '../../docs/presentation/abstract_body.dart';
import '../../notifications/data/ask_resolution.dart';
import '../../notifications/data/voice_persona.dart';
import '../../notifications/presentation/interactive_prompt_sheet.dart';
import '../../notifications/presentation/message_stamp.dart';
import '../../notifications/presentation/mute_sender_action.dart';
import '../../notifications/presentation/persona_badge.dart';
import '../domain/focus_chat_bloc.dart';
import '../domain/focus_chat_event.dart';
import '../domain/focus_chat_state.dart';
import 'tts_fraction_bar.dart';

/// The chat half of the focus surface: header, the focused sender's window, inline prompts.
///
/// The header shows the sender's badge and name. The window holds the last seven messages,
/// newest at the top. Inline prompts attach to the newest unanswered ask only, through
/// `pendingPromptFor`. Cold start shows an empty-state hint, a loading spinner or an error
/// retry banner.
///
/// Inline responses dispatch `FocusRespondRequested` with an explicit typed
/// `FocusPromptContext`. Batch open-ended asks and multi-select multiple-choice asks show a
/// fallback button that opens the legacy `InteractivePromptSheet`.
class FocusChatPane extends StatefulWidget {
  /// Authenticated email that the error banner's retry needs for `FocusColdStartRequested`.
  final String? userEmail;
  /// Stop-list preferences, including the collapse toggle.
  ///
  /// Tests inject it, production resolves it from the locator when registered, and null
  /// collapses groups, matching the browser.
  final NotificationStopList? stopList;
  /// Audio preferences for the pinned TTS-fraction slider.
  ///
  /// Tests inject it, production resolves it from the locator, and null renders no slider.
  final NotificationPreferences? prefs;

  /// Creates the pane; [userEmail] feeds the retry banner.
  const FocusChatPane( { super.key, this.userEmail, this.stopList, this.prefs } );

  /// Share of the pane's width a bubble may use.
  ///
  /// A fixed 320 px cap left bubbles at about half the width of an unfolded Pixel Fold.
  /// The header spanned all of it, so the cap now follows the screen.
  static const double bubbleWidthFraction = 0.9;

  @override
  State<FocusChatPane> createState() => _FocusChatPaneState();
}

class _FocusChatPaneState extends State<FocusChatPane> {
  NotificationStopList?    _stopList;
  NotificationPreferences? _prefs;
  String? get userEmail => widget.userEmail;

  /// Attached to the message list so a notification tap can bring its message into view.
  ///
  /// One controller serves the pane across sender switches: the list is rebuilt, the
  /// controller is not.
  final ScrollController _listScroll = ScrollController();

  /// The scroll anchor for the message a notification tap asked to reveal.
  ///
  /// It is one long-lived `GlobalKey`, not a `GlobalObjectKey` built from the id.
  /// A `GlobalObjectKey` compares its value with `identical()`, not `==`. Two separately
  /// interpolated strings with the same characters are equal but not identical.
  /// A key built in the build method and an equal-looking one built in the callback would
  /// therefore differ. Then `currentContext` would be null and the scroll would never happen.
  /// One key is enough because there is at most one reveal target at a time.
  final GlobalKey _revealAnchor = GlobalKey();

  /// The reveal target this pane has already acted on, so the scroll fires once per tap.
  ///
  /// Without it every unrelated rebuild would scroll the list back under a user who has
  /// since scrolled elsewhere.
  String? _revealedId;

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
    _listScroll.dispose();
    super.dispose();
  }

  /// Scrolls the bubble for [notificationId] into view, then tells the bloc it is done.
  ///
  /// The list is a scroll view over a column, so every bubble in the window is built.
  /// The target is found unless its message has left the window. In that case the reveal
  /// is consumed and the list stays where it is. The sender is still selected.
  void _revealAfterFrame( String notificationId ) {
    WidgetsBinding.instance.addPostFrameCallback( ( _ ) async {
      if ( !mounted ) return;
      final ctx = _revealAnchor.currentContext;
      if ( ctx != null ) {
        await Scrollable.ensureVisible(
          ctx,
          alignment : 0.1,                              // just below the top edge
          duration  : const Duration( milliseconds: 250 ),
          curve     : Curves.easeOut,
        );
      }
      if ( !mounted ) return;
      context.read<FocusChatBloc>().add( const FocusRevealConsumed() );
    } );
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
            // Pinned above everything else in the pane; it survives sender switches and
            // the loading and error states.
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
      // Cold-start empty state: nothing is focused until the user taps a badge.
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
    final personaRaw   = ( persona?.displayName ?? persona?.name ?? '' ).trim();
    final personaLabel = personaRaw.isEmpty ? null : personaRaw;

    // Stop-list render lens: ingest suppression only catches new arrivals, so a pattern
    // checked after a bubble landed would leave it on screen. The same predicate is
    // applied here. The window is retained, so unchecking reveals again instantly, and the
    // pane re-renders on any stop-list change through [_onPrefsChanged].
    // User replies and actionable questions are never hidden. The bloc exempts an
    // actionable question at ingest, and this lens is the second enforcement point of that
    // rule. Hiding the question here would leave the user asked to act on something they
    // cannot see, while the server blocks on a reply they cannot send.
    // [isActionableQuestion] is reused, not re-implemented, so both points share one
    // predicate.
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

    // The keyboard can leave this pane less height than its own header: with the DM editor
    // open and the soft keyboard up at 360x800, the pane gets about 35 dp against a 44 dp
    // header. Below this floor the chrome steps aside and the list takes the space.
    return LayoutBuilder( builder: ( context, box ) {
      final roomy = box.maxHeight >= _kHeaderFloor;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: badge + sender name.
          if ( roomy ) Padding(
            padding: const EdgeInsets.symmetric( horizontal: 12, vertical: 8 ),
            child: Row(
              children: [
                if ( persona != null )
                  PersonaBadge( persona: persona, senderId: focused, diameter: 28 ),
                if ( persona != null ) const SizedBox( width: 8 ),
                // Persona name first and bold; the sender id stays, italic and quieter, so
                // both read at a glance.
                if ( personaLabel != null ) ...[
                  Text(
                    personaLabel,
                    key   : const Key( TestKeys.focusHeaderPersonaName ),
                    style : Theme.of( context ).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold ),
                  ),
                  const SizedBox( width: 8 ),
                ],
                Expanded(
                  child: Text(
                    focused,
                    key      : const Key( TestKeys.focusHeaderSenderId ),
                    style    : Theme.of( context ).textTheme.bodySmall?.copyWith(
                      fontStyle : FontStyle.italic,
                      color     : Theme.of( context ).colorScheme.outline,
                    ),
                    overflow : TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if ( roomy ) const Divider( height: 1 ),
          if ( roomy && hidden > 0 )
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
                    // Newest at the top: the window is stored oldest to newest. Group first,
                    // since runs are contiguous either way, then render the groups reversed.
                    // Inside an expanded group the children are newest first too.
                    final groups = collapseByProgressGroup<FocusMessage>(
                      window, _groupKey, enabled: _stopList?.collapseGroups ?? true )
                      .reversed.toList( growable: false );

                    // A notification tap asks to reveal one message. Honour it only while the
                    // target is in this sender's window: an evicted or stop-listed target has
                    // nothing to scroll to, and must still be consumed so the pane does not
                    // retry it on every rebuild.
                    final reveal = state.revealMessageId;
                    final inWindow = reveal != null &&
                        window.any( ( m ) => m.item.id == reveal );
                    // Do not consume a reveal while the backfill is in flight: on a cold start the
                    // tap is routed before the conversation fetch returns, and consuming on a
                    // window that lacks the target would discard the reveal one frame before its
                    // message arrives. The loading branch of [_body] already shows a spinner
                    // instead of this list, so this is a second guard. It protects a one-shot
                    // instruction from being spent on an incomplete window, and a later change
                    // to the loading branch should not reintroduce the bug.
                    final settled = state.hydration != FocusHydration.loading;
                    if ( reveal != null && settled && reveal != _revealedId ) {
                      _revealedId = reveal;
                      _revealAfterFrame( reveal );
                    }
                    if ( reveal == null ) _revealedId = null;

                    // A scroll view over a column, not a `ListView`, because the reveal needs
                    // every bubble to exist. `Scrollable.ensureVisible` only reaches an element
                    // that exists, and both `ListView` forms build only the visible range plus
                    // the cache. In a 320 dp viewport a seven-message window put only five
                    // bubbles in the tree, and raising `cacheExtent` or passing pre-built
                    // children changed nothing. This is cheap because the bloc caps the window
                    // at seven messages per sender; if that cap rises materially, revisit this.
                    return SingleChildScrollView(
                      controller  : _listScroll,
                      padding     : const EdgeInsets.all( 8 ),
                      child       : Column(
                        crossAxisAlignment : CrossAxisAlignment.stretch,
                        children           : [ for ( var i = 0; i < groups.length; i++ )
                        ( ( ) {
                        final g = groups[ i ];
                        final holdsTarget = inWindow &&
                            g.items.any( ( m ) => m.item.id == reveal );
                        if ( !g.isCollapsed ) {
                          final m = g.items.single;
                          final bubble = _MessageBubble(
                            msg            : m,
                            senderId       : focused,
                            personaColor   : PersonaBadge.colorOf( persona ),
                            isPendingPrompt: pending?.item.id == m.item.id,
                            persona        : persona,
                            prefs          : _prefs,
                          );
                          // The scroll anchor rides a wrapper, not the bubble: the bubble
                          // already carries its own key, which tests match on, and a widget
                          // cannot hold two.
                          return holdsTarget
                              ? KeyedSubtree(
                                  key   : _revealAnchor,
                                  child : bubble )
                              : bubble;
                        }
                        final group = _CollapsedGroup(
                          key      : Key( '${TestKeys.focusGroupPrefix}${g.key}-${g.latest.item.id}' ),
                          count    : g.count,
                          // A buried target is expanded, or ensureVisible has no element to find.
                          initiallyExpanded : holdsTarget,
                          summary  : _MessageBubble( msg: g.latest, senderId: focused,
                              personaColor: PersonaBadge.colorOf( persona ), isPendingPrompt: false,
                              persona: persona, prefs: _prefs ),
                          children : [ for ( final m in g.items.reversed )
                            _MessageBubble( msg: m, senderId: focused,
                                personaColor: PersonaBadge.colorOf( persona ), isPendingPrompt: false,
                                persona: persona, prefs: _prefs ) ],
                        );
                        return holdsTarget
                            ? KeyedSubtree(
                                key   : _revealAnchor,
                                child : group )
                            : group;
                        } )() ],
                      ),
                    );
                  } ),
          ),
        ],
      );
    } );
  }
}

/// Height below which the pane shows its list alone, with no header.
///
/// It is the header (about 44 dp), divider and stop-list caption, rounded up. See the
/// keyboard note in the pane's build.
const double _kHeaderFloor = 96;

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
  final Color?       personaColor;
  final bool         isPendingPrompt;

  /// Who sent it, for the long-press "Mute <sender>" shortcut.
  ///
  /// The prefs are what that shortcut writes to; null falls back to the locator.
  final VoicePersona?            persona;
  final NotificationPreferences? prefs;

  const _MessageBubble( {
    required this.msg,
    required this.senderId,
    required this.isPendingPrompt,
    this.personaColor,
    this.persona,
    this.prefs,
  } );

  /// The accent colours by priority, used for a sender with no colour of its own.
  ///
  /// The bar normally names the sender, so each sender's bubbles differ.
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
    final accent = personaColor ?? _priorityAccent[ msg.item.priority ] ?? Colors.blueGrey;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if ( msg.item.title != null && msg.item.title!.isNotEmpty )
          Text( msg.item.title!, style: theme.textTheme.labelLarge ),
        Text( msg.item.message ),
        // The abstract carries doc links. The card renders nothing for an empty abstract,
        // and the repository is only looked up when there is one to show.
        if ( msg.item.abstractText?.isNotEmpty ?? false ) ...[
          const SizedBox( height: 6 ),
          AbstractBody(
            abstractText : msg.item.abstractText,
            repository   : ServiceLocator.instance<DocRepository>(),
          ),
        ],
        // A question the stop-list suppressed says so, names the rule, and offers
        // speak-anyway. It renders above the prompt zone so the normal answer controls
        // stay intact and the user can still answer silently.
        if ( msg.suppressedRule != null )
          _SuppressedNotice( msg: msg ),
        if ( msg.item.responseRequested ) _promptZone( context ),
        const SizedBox( height: 2 ),
        MessageStamp( timestamp: msg.item.timestamp, id: msg.item.id ),   // lower-left
      ],
    );

    return LayoutBuilder( builder: ( context, box ) => Align(
      alignment: _isUserReply ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        // Your own replies have no sender to mute.
        onLongPress: _isUserReply ? null : () => showMuteSenderMenu(
          context,
          item  : senderItemFor( senderId, persona ),
          prefs : prefs,
        ),
        child: Container(
          key        : Key( '${TestKeys.focusBubblePrefix}${msg.item.id}' ),
          margin     : const EdgeInsets.symmetric( vertical: 4 ),
          constraints: BoxConstraints(
            maxWidth: box.maxWidth * FocusChatPane.bubbleWidthFraction,
          ),
          clipBehavior: Clip.antiAlias,
          decoration : BoxDecoration(
            color: _isUserReply
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular( 10 ),
          ),
          // The content sizes itself and the accent bar is laid over its left edge. An
          // `IntrinsicHeight` around a `Row` underestimated wrapped choice tiles at phone
          // widths, which clipped the Submit button of an inline multiple-choice ask.
          child: Stack(
            children: [
              Padding(
                padding : EdgeInsets.fromLTRB( _isUserReply ? 10 : 13, 10, 10, 10 ),
                child   : content,
              ),
              // Sender-colour accent bar (Claude-sent bubbles only).
              if ( !_isUserReply )
                Positioned( left: 0, top: 0, bottom: 0,
                    child: Container( width: 3, color: accent ) ),
            ],
          ),
        ),
      ),
    ) );
  }

  Widget _promptZone( BuildContext context ) {
    // An answer that never left the phone says so on its card instead of vanishing.
    final unsent = msg.unsentAnswer;
    if ( unsent != null ) {
      final theme = Theme.of( context );
      if ( msg.answered ) {
        final why = msg.resolution == AskResolution.expired
            ? 'Expired — your answer "$unsent" was not sent'
            : 'Closed before your answer "$unsent" was sent';
        return Padding(
          padding : const EdgeInsets.only( top: 6 ),
          child   : Row( mainAxisSize: MainAxisSize.min, children: [
            Icon( Icons.cloud_off, size: 16, color: theme.colorScheme.error ),
            const SizedBox( width: 6 ),
            Flexible( child: Text( why,
              key   : const Key( TestKeys.focusUnsentClosed ),
              style : theme.textTheme.bodySmall?.copyWith( color: theme.colorScheme.error ) ) ),
          ] ),
        );
      }
      return Column(
        crossAxisAlignment : CrossAxisAlignment.start,
        mainAxisSize       : MainAxisSize.min,
        children: [
          Padding(
            padding : const EdgeInsets.only( top: 6 ),
            child   : TextButton.icon(
              key       : const Key( TestKeys.focusUnsentResend ),
              icon      : Icon( Icons.sync_problem, size: 16, color: theme.colorScheme.error ),
              label     : Text( 'Not sent: "$unsent" — tap to resend',
                  style: TextStyle( color: theme.colorScheme.error ) ),
              onPressed : () => context.read<FocusChatBloc>().add( FocusRespondRequested(
                senderId      : senderId,
                text          : unsent,
                promptContext : FocusPromptContext( notificationId: msg.item.id, promptType: msg.item.responseType ),
              ) ),
            ),
          ),
          _promptControls( context ),
        ],
      );
    }
    return _promptControls( context );
  }

  Widget _promptControls( BuildContext context ) {
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
      // Unanswered but not the newest unanswered ask: buttons attach only through
      // pendingPromptFor, so one ask is actionable at a time.
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
    // Backfilled multiple_choice asks carry null options, because the conversation wire
    // never emits response_options. Chips can only render from a live payload.
    final optionsRenderable = opts?[ 'options' ] is List;
    // A canonical `ask_multiple_choice` payload nests its questions under
    // `response_options.questions[]`, so `optionsRenderable` is false for it. It renders
    // inline through the same promoted body the sheet uses.
    final nestedAll = ( opts?[ 'questions' ] as List? )?.cast<dynamic>() ?? const [];
    // Scoped to multiple_choice: `open_ended_batch` keeps its route to the legacy sheet,
    // and letting the inline path take batch asks would be a further behaviour change.
    final nested = type == 'multiple_choice' ? nestedAll : const [];

    if ( nested.isEmpty &&
        ( type == 'open_ended_batch' ||
        ( type == 'multiple_choice' && ( multi || !optionsRenderable ) ) ) ) {
      // Map- and list-valued asks stay string-free on the focus path, and backfilled
      // choice asks without options have nothing to chip. Both get the fallback button
      // that opens the legacy sheet.
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
      // The server parser wants {"answers": {header: value}}; the body stays
      // door-agnostic and this host wraps it.
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
          // A single-select value is always a String (see prompt_bodies.dart), so it is
          // safe on the String-typed focus path.
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

/// One expandable row standing in for a burst of same-progress-group messages.
///
/// The latest message is the summary, a count badge sits beside it, and a tap expands or
/// collapses in place. The state is render-only.
class _CollapsedGroup extends StatefulWidget {
  final int          count;
  final Widget       summary;
  final List<Widget> children;

  /// Starts open because a notification tap points at a message inside this group.
  ///
  /// Scrolling to a bubble that is not built resolves to nothing, so a buried target is
  /// expanded first. The user keeps the toggle and can fold it again.
  final bool         initiallyExpanded;

  const _CollapsedGroup( { super.key, required this.count, required this.summary,
      required this.children, this.initiallyExpanded = false } );

  @override
  State<_CollapsedGroup> createState() => _CollapsedGroupState();
}

class _CollapsedGroupState extends State<_CollapsedGroup> {
  late bool _expanded = widget.initiallyExpanded;

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

/// The notice on a suppressed question: it names the matching rule and offers speak-anyway.
///
/// The stop-list holds: `verbatim` bypasses the second and third gates only, and a flag does
/// not override a pattern the user typed. A silently dropped question is indistinguishable
/// from a hang, because the server blocks waiting for the user. So the suppression is made
/// visible instead: the text is always on screen, the rule is named, and one tap speaks it.
///
/// It is expected to fire rarely, since the stop-list targets repetitive event chatter,
/// which seldom overlaps a question.
/// Design: src/docs/decisions/README.md (R-FM-show-suppressed-ask)
class _SuppressedNotice extends StatelessWidget {
  final FocusMessage msg;

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
          // Offered only when the original suppression was retained: it is the object the
          // first gate produced, handed straight back, so what plays is what was refused
          // and not a reconstruction guessing `verbatim` and `sender`.
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
