/// Stable widget keys for UI tests (widget + integration + future Patrol/Maestro).
///
/// Production code attaches these via `Key( TestKeys.xxx )`; test code
/// looks them up via `find.byKey( Key( TestKeys.xxx ) )`. A single source
/// of truth prevents selector drift as UI copy/structure evolves and
/// survives i18n (unlike `find.text`).
class TestKeys {
  TestKeys._();

  // Login
  static const loginEmailField    = 'login.email';
  static const loginPasswordField = 'login.password';
  static const loginSubmitButton  = 'login.submit';

  // Inbox — suffixed with senderId at use-site, e.g. '${inboxSenderTilePrefix}s-1'
  static const inboxSenderTilePrefix = 'inbox.sender.';

  // Conversation / InteractivePromptSheet
  static const convRespondButtonPrefix = 'conv.respond.'; // + messageId
  static const convSummarizeButton     = 'conv.summarize';
  static const convDatesButton         = 'conv.dates';
  static const convGistSheet           = 'conv.gistSheet';
  static const promptYesButton         = 'prompt.yes';
  static const promptNoButton          = 'prompt.no';
  static const promptNeitherButton     = 'prompt.neither';
  static const promptCommentField      = 'prompt.comment';
  /// Submit button of the promoted multi-question body (AC-S4.16).
  static const promptMultiQuestionSubmit = 'prompt.multiQuestion.submit';

  // Sender-dates drilldown
  static const senderDatesTilePrefix          = 'senderDates.tile.';        // + date

  // Conversation by date
  static const convByDateSectionHeaderPrefix  = 'convByDate.section.';      // + date
  static const convByDateItemPrefix           = 'convByDate.item.';         // + notificationId
  static const convByDateRespondPrefix        = 'convByDate.respond.';      // + notificationId

  // Trust Dashboard — per-decision actions
  static const trustDecisionCardPrefix = 'trust.decision.';        // + decisionId
  static const trustDecisionApprovePrefix = 'trust.decision.approve.'; // + decisionId
  static const trustDecisionRejectPrefix  = 'trust.decision.reject.';  // + decisionId

  // Trust State drilldown (per-domain trust details)
  static const trustViewDetailsButton          = 'trust.viewDetails';
  static const trustStateRowPrefix             = 'trust.state.row.';     // + '<domain>:<category>'
  static const trustStateDomainHeaderPrefix    = 'trust.state.domain.';  // + domain

  // Abstract rendering + doc-link viewer
  static const abstractBody         = 'docs.abstract.body';
  static const abstractDocBadge     = 'docs.abstract.badge';
  static const abstractExpandToggle = 'docs.abstract.expand';
  static const docViewerScreen      = 'docs.viewer.screen';
  static const docViewerMarkdown    = 'docs.viewer.markdown';
  static const docViewerSource      = 'docs.viewer.source';
  static const docViewerImage       = 'docs.viewer.image';
  static const docViewerError       = 'docs.viewer.error';
  static const docViewerShareButton = 'docs.viewer.share';
  static const docDirEntryPrefix    = 'docs.dir.entry.';   // + entry name

  // Deep research form
  static const drQueryField     = 'dr.query';
  static const drDryRunCheckbox = 'dr.dryRun';
  static const drSubmitButton   = 'dr.submit';

  // Podcast generator form (pg = podcast generator)
  static const pgSourceField    = 'pg.source';
  static const pgDryRunSwitch   = 'pg.dryRun';
  static const pgSubmitButton   = 'pg.submit';

  // Presentation generator form (px = presentation; avoids clash with pg)
  static const pxSourceField       = 'px.source';
  static const pxRenderOnlySwitch  = 'px.renderOnly';
  static const pxDryRunSwitch      = 'px.dryRun';
  static const pxSubmitButton      = 'px.submit';

  // SWE Team form
  static const swTaskField      = 'sw.task';
  static const swSubmitButton   = 'sw.submit';

  // Bug Fix Expediter form
  static const bfeDeadJobIdField = 'bfe.deadJobId';
  static const bfeDryRunSwitch   = 'bfe.dryRun';
  static const bfeSubmitButton   = 'bfe.submit';

  // Test Fix Expediter form (Resume-from flow)
  static const tfeResumeFromField = 'tfe.resumeFrom';
  static const tfeSubmitButton    = 'tfe.submit';

  // Test Suite form (prefix suffixed with test type at use-site)
  static const tsTestTypeCheckboxPrefix = 'ts.type.';  // + testType name
  static const tsAutoFixSwitch          = 'ts.autoFix';
  static const tsDryRunSwitch           = 'ts.dryRun';
  static const tsSubmitButton           = 'ts.submit';

  // Research → Podcast form (rp)
  static const rpQueryField     = 'rp.query';
  static const rpDryRunSwitch   = 'rp.dryRun';
  static const rpSubmitButton   = 'rp.submit';

  // Research → Presentation form (rx)
  static const rxQueryField     = 'rx.query';
  static const rxDryRunSwitch   = 'rx.dryRun';
  static const rxSubmitButton   = 'rx.submit';

  // Notification audio settings (six toggles)
  static const settingsDingMedium   = 'settings.audio.dingMedium';
  static const settingsDingHigh     = 'settings.audio.dingHigh';
  static const settingsDingUrgent   = 'settings.audio.dingUrgent';
  static const settingsSpeakHigh    = 'settings.audio.speakHigh';
  static const settingsSpeakUrgent  = 'settings.audio.speakUrgent';
  static const settingsMasterMute   = 'settings.audio.masterMute';
  static const settingsSpeakSystem  = 'settings.audio.speakSystemSenders';

  // Home screen AppBar
  static const homeSettingsButton   = 'home.settings';

  // Voice persona badge (Phase 3 — voice-persona milestone)
  // Used at every wiring site (inbox tile, conversation header, by-date item).
  // Suffix with senderId at use-site, e.g. '${personaBadgePrefix}s-1'.
  static const personaBadgePrefix       = 'persona.badge.';        // + senderId
  static const personaBadgeDashedPrefix = 'persona.badge.dashed.'; // + senderId (borrowed variant)
  static const personaBadgeDottedPrefix = 'persona.badge.dotted.'; // + senderId (overflow variant — Section C / Phase 3)

  // Focus-mode surface (S3 — focus-mode-voice-chat milestone)
  static const focusRail            = 'focus.rail';
  static const focusRailBadgePrefix = 'focus.rail.badge.';   // + senderId
  static const focusPauseToggle     = 'focus.pauseToggle';
  static const focusChatPane        = 'focus.chatPane';
  static const focusDrawerButton    = 'focus.drawerButton';
  static const focusPausedBanner    = 'focus.pausedBanner';
  static const focusRetryBanner     = 'focus.retryBanner';
  static const focusBatchFallbackPrefix = 'focus.batchFallback.';  // + notificationId
  // Focus rail visibility lens (2026.06.25 plan, built 2026-08-21)
  static const focusFilterBar            = 'focus.filterBar';
  static const focusFilterLive           = 'focus.filter.live';
  static const focusFilterHistory        = 'focus.filter.history';
  static const focusScopePersonas        = 'focus.scope.personas';
  static const focusScopeAll             = 'focus.scope.all';
  static const focusRailGroupDivider     = 'focus.rail.groupDivider';
  static const focusComposerCaption      = 'focus.composer.caption';
  static const focusQueueButton          = 'focus.queueButton';
  static const focusQueueBadge           = 'focus.queueButton.badge';
  static const ttsQueueSheet             = 'ttsQueue.sheet';
  static const ttsQueueEmpty             = 'ttsQueue.empty';
  static const ttsQueueSkip              = 'ttsQueue.skip';
  static const ttsQueueClear             = 'ttsQueue.clear';
  static const ttsQueueStopAll           = 'ttsQueue.stopAll';
  static const ttsQueueRowPrefix         = 'ttsQueue.row.';      // + item id
  static const ttsQueueDeletePrefix      = 'ttsQueue.delete.';   // + item id
  static const focusRailStatusDotPrefix  = 'focus.rail.dot.';      // + senderId
  static const focusRailInitialPrefix    = 'focus.rail.initial.';  // + senderId (fallback avatar)
  static const focusRailEmptyHint        = 'focus.rail.emptyHint';
  static const focusRailEmptyHintButton  = 'focus.rail.emptyHint.button';
  // Notification stop-list (plan 2026.08.21 §3)
  static const focusHiddenCaption            = 'focus.hiddenCaption';
  static const conversationHiddenChip        = 'conversation.hiddenChip';
  static const settingsOpenStopList          = 'settings.audio.openStopList';
  static const settingsStopListAddField      = 'settings.stopList.addField';
  static const settingsStopListAddButton     = 'settings.stopList.addButton';
  static const settingsStopListMenu          = 'settings.stopList.menu';
  static const settingsStopListReset         = 'settings.stopList.reset';
  static const settingsStopListRowPrefix     = 'settings.stopList.row.';      // + pattern
  static const settingsStopListTogglePrefix  = 'settings.stopList.toggle.';   // + pattern
  // TTS preview-fraction slider pinned at the top of the focus pane (Rick 2026-08-21)
  static const focusTtsFractionBar             = 'focus.ttsFraction.bar';
  static const focusTtsFractionSlider          = 'focus.ttsFraction.slider';
  static const focusTtsFractionValue           = 'focus.ttsFraction.value';
  // Lower-left timestamp on every notification bubble/card (Rick 2026-08-21)
  static const messageStampPrefix              = 'message.stamp.';             // + notification id
  // Progress-group collapse (plan 2026.08.21 §4)
  static const settingsCollapseGroups          = 'settings.collapseGroups';
  static const focusGroupPrefix                = 'focus.group.';               // + groupKey-latestId
  static const focusGroupTogglePrefix          = 'focus.group.toggle.';        // + Key(...).toString()
  static const conversationGroupPrefix         = 'conversation.group.';        // + groupKey-latestId
  static const conversationGroupTogglePrefix   = 'conversation.group.toggle.'; // + Key(...).toString()

  // Focus-mode voice reply composer (S4 — focus-mode-voice-chat milestone)
  static const voiceReplyMic        = 'voiceReply.mic';
  static const voiceReplyTranscript = 'voiceReply.transcript';
  static const voiceReplySend       = 'voiceReply.send';
  static const voiceReplyCancel     = 'voiceReply.cancel';
  static const voiceReplyError      = 'voiceReply.error';   // F-S4-S2-1a affordance (AC-S4.8)

  // Audio artifact player (Phase 4a — in-app playback for pg-* / rp- jobs)
  static const audioPlayerDownloadButton = 'audio.download';
  static const audioPlayerPlayButton     = 'audio.play';
  static const audioPlayerPauseButton    = 'audio.pause';
  static const audioPlayerStopButton     = 'audio.stop';
  static const audioPlayerShareButton    = 'audio.share';
  static const audioPlayerSlider         = 'audio.slider';

  // ── Quick Ask (S2) ──────────────────────────────────────────────────────
  static const quickAskRecordButton   = 'quickAsk.record';
  static const quickAskClearButton    = 'quickAsk.clear';
  static const quickAskSendButton     = 'quickAsk.send';
  static const quickAskDraftText      = 'quickAsk.draft';
  static const quickAskBlockedReason  = 'quickAsk.blockedReason';
  static const quickAskError          = 'quickAsk.error';
  static const quickAskList           = 'quickAsk.list';
  static const quickAskEmpty          = 'quickAsk.empty';
  static const quickAskLostBanner     = 'quickAsk.lost';
  static const quickAskCardPrefix     = 'quickAsk.card.';      // + jobId
  static const quickAskCardDismissPrefix = 'quickAsk.card.dismiss.'; // + jobId
  static const quickAskChipPrefix     = 'quickAsk.chip.';      // + lane name
  static const quickAskAnswerPrefix   = 'quickAsk.answer.';    // + jobId
  static const quickAskErrorCardPrefix = 'quickAsk.errorCard.';// + jobId
  static const quickAskProgressPrefix = 'quickAsk.progress.';  // + jobId
  static const quickAskPauseToggle    = 'quickAsk.pauseToggle';
  static const quickAskPausedBanner   = 'quickAsk.pausedBanner';
  static const quickAskReplayPrefix   = 'quickAsk.replay.';      // + jobId
  static const quickAskInterview      = 'quickAsk.interview';
  static const quickAskInterviewQ     = 'quickAsk.interview.question';
  static const quickAskInterviewCancel= 'quickAsk.interview.cancel';
  static const quickAskNeedsInputCard = 'quickAsk.needsInput';
  // AC-S4.6 — the Door C interlock surface, live WHILE an ask is in flight.
  static const quickAskPrompt         = 'quickAsk.prompt';
  static const quickAskPromptQuestion = 'quickAsk.prompt.question';
  static const quickAskPromptDismiss  = 'quickAsk.prompt.dismiss';

  // ── Suppressed-question notice (S4.14 / S4.15) ──────────────────────────
  static const promptSuppressedNotice = 'prompt.suppressed.notice';
  static const promptSuppressedRule   = 'prompt.suppressed.rule';
  static const promptSpeakAnyway      = 'prompt.suppressed.speakAnyway';
}
