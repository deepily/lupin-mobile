/// Stable widget keys for UI tests (widget + integration + future Patrol/Maestro).
///
/// Production code attaches these via `Key( TestKeys.xxx )`; test code
/// looks them up via `find.byKey( Key( TestKeys.xxx ) )`. A single source
/// of truth prevents selector drift as UI copy/structure evolves and
/// survives i18n (unlike `find.text`).
class TestKeys {
  TestKeys._();

  // Login
  static const loginEmailField         = 'login.email';
  static const loginPasswordField      = 'login.password';
  static const loginSubmitButton       = 'login.submit';
  static const loginPasswordVisibility = 'login.passwordVisibility';

  // Server switch (ServerContextToggle) — segments suffixed with the context
  // id from server-contexts.json, e.g. '${serverContextSegmentPrefix}lan-dev'
  static const serverContextToggle        = 'server_context.toggle';
  static const serverContextSegmentPrefix = 'server_context.segment.';

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
  static const abstractOpenButton   = 'docs.abstract.open';   // opens the whole abstract (2026-09-18)
  static const docViewerScreen      = 'docs.viewer.screen';
  static const docPanel             = 'docs.panel';
  static const docSplitRow          = 'docs.split.row';
  static const docSplitColumn       = 'docs.split.column';
  static const docViewerMarkdown    = 'docs.viewer.markdown';
  static const docViewerSource      = 'docs.viewer.source';
  static const docViewerImage       = 'docs.viewer.image';
  static const docViewerError       = 'docs.viewer.error';
  static const docViewerShareButton = 'docs.viewer.share';
  static const docViewerCloseButton = 'docs.viewer.close';
  static const docViewerPlacementToggle = 'docs.viewer.placement';   // beside ⇄ below on a wide screen
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
  static const homeFleetStatusCard  = 'home.fleetStatus';
  static const homeLupinFocusCard   = 'home.lupinFocus';

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
  static const focusDrawerLogout    = 'focus.drawerLogout';
  static const focusComposerScroll  = 'focus.composerScroll';
  static const focusPausedBanner    = 'focus.pausedBanner';
  static const focusRetryBanner     = 'focus.retryBanner';
  static const focusBatchFallbackPrefix = 'focus.batchFallback.';  // + notificationId
  static const focusBubblePrefix        = 'focus.bubble.';         // + notificationId
  static const focusHeaderPersonaName   = 'focus.header.personaName';
  static const focusHeaderSenderId      = 'focus.header.senderId';
  // Focus rail visibility lens (2026.06.25 plan, built 2026-08-21)
  static const focusFilterBar            = 'focus.filterBar';
  static const focusFilterLive           = 'focus.filter.live';
  static const focusFilterHistory        = 'focus.filter.history';
  static const focusScopePersonas        = 'focus.scope.personas';
  static const focusScopeAll             = 'focus.scope.all';
  static const focusRailGroupDivider     = 'focus.rail.groupDivider';
  static const focusComposerCaption      = 'focus.composer.caption';
  static const focusQueueButton          = 'focus.queueButton';
  static const focusRosterRefreshButton  = 'focus.rosterRefreshButton';
  static const focusUnsentResend         = 'focus.unsent.resend';   // row b00e076c
  static const focusUnsentClosed         = 'focus.unsent.closed';
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
  // Debug: network round-trip probe (task c51e92da)
  static const settingsOpenRoundTripProbe    = 'settings.debug.openRoundTripProbe';
  // Debug: keep voice recordings as WAV (row 9b1f7701)
  static const settingsKeepVoiceRecordings   = 'settings.debug.keepVoiceRecordings';
  static const probeRunButton                = 'probe.run';
  static const probeCopyPathButton           = 'probe.copyPath';
  static const probeProgress                 = 'probe.progress';
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
  static const quickAskSendModeToggle = 'quickAsk.sendMode';
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

  // ── Finished Tasks pane (Phase 2) ───────────────────────────────────────
  // The row cell keys are suffixed with the EVENT id at the use site, so a test
  // can assert the four cells of one identified row rather than counting widgets.
  static const finishedRefreshButton    = 'finished.refresh';
  static const finishedStatusPillPrefix = 'finished.pill.';      // + status
  static const finishedWindowSlider     = 'finished.window.slider';
  static const finishedWindowLabel      = 'finished.window.label';
  static const finishedPartialBanner    = 'finished.partialBanner';
  static const finishedEmptyState       = 'finished.empty';
  static const finishedErrorView        = 'finished.error';
  static const finishedRowGlyphPrefix   = 'finished.row.glyph.';  // + event id
  static const finishedRowWhenPrefix    = 'finished.row.when.';   // + event id
  static const finishedRowTitlePrefix   = 'finished.row.title.';  // + event id
  static const finishedRowWhoPrefix     = 'finished.row.who.';    // + event id
  static const finishedRowWhyPrefix     = 'finished.row.why.';    // + event id
  // ── Fleet Status pane (fleet-panes plan Phase 1, row a1962a5b) ──────────
  static const fleetStatusList        = 'fleetStatus.list';
  static const fleetStatusOfflineToggle = 'fleetStatus.offlineToggle';
  /// Suffixed with the row's session id, e.g. '${fleetStatusRowPrefix}078b97cb'.
  static const fleetStatusRowPrefix   = 'fleetStatus.row.';
  /// The Liveness cell — a TAP target here, because a phone has no hover.
  static const fleetStatusLivenessPrefix = 'fleetStatus.liveness.';
  static const fleetStatusLivenessSheet  = 'fleetStatus.livenessSheet';
  /// 🔴 DISTINCT FROM THE EMPTY STATE ON PURPOSE. The server answers
  /// `status: "unreachable"` with an HTTP 200, so "we cannot see the fleet" and
  /// "the fleet has no seats" must be two different things on screen.
  static const fleetStatusUnreachable = 'fleetStatus.unreachable';
  static const fleetStatusEmpty       = 'fleetStatus.empty';
  // The fleet-size cap dial — a real write, PUT /api/arbiter/fleet-size-cap.
  static const fleetStatusCapDial     = 'fleetStatus.capDial';
  static const fleetStatusCapValue    = 'fleetStatus.capValue';
  static const fleetStatusCapApply    = 'fleetStatus.capApply';

  // ── Fleet panes: the SHARED task row (Phase 0) ──────────────────────────
  //
  // 🔴 THE CELL PREFIX IS THE CELL-IDENTITY GUARD'S ONLY HANDLE, AND THAT IS WHY IT
  // EXISTS. `find.byType( TaskRow )` passes while the two panes drift four different
  // ways — a `pane:` parameter branching inside, different field subsets, a bespoke row
  // for a special case, or a wrapper. Selecting the ORDERED CELL KEYS catches all four,
  // because it compares what was actually rendered rather than which class rendered it.
  static const taskRowCellPrefix    = 'taskRow.cell.';      // + RowCell.key
  static const taskRowDisclosure    = 'taskRow.disclosure';
  static const taskRowControls      = 'taskRow.controls';
  static const taskRowVerbPrefix    = 'taskRow.verb.';      // + verb name

  // ── The SHARED verb reason sheet (Phase 2 interactivity, row e10d8074) ──
  //
  // 🔴 NO PANE SEGMENT IN ANY OF THESE KEYS, AND THE ABSENCE IS DELIBERATE. The sheet
  // takes no pane parameter, so a key like `reasonSheet.taskList.reason` could only come
  // from a sheet that had grown one. A test naming a pane here would make that drift
  // look intentional.
  static const reasonSheet          = 'reasonSheet';
  static const reasonSheetReason    = 'reasonSheet.reason';
  static const reasonSheetDate      = 'reasonSheet.date';
  static const reasonSheetDateError = 'reasonSheet.dateError';
  static const reasonSheetSubmit    = 'reasonSheet.submit';
  static const reasonSheetCancel    = 'reasonSheet.cancel';
  static const reasonSheetNoReason  = 'reasonSheet.noReasonNotice';

  // ── The SHARED field-door controls (G2) ─────────────────────────────────
  //
  // 🔴 NAMED FOR THE DOOR, NOT FOR THE PANE. These two keys are the FIELD door — the
  // PATCH that may carry `priority` and `owner_persona` and nothing else. A test that
  // finds `taskField.*` on a request carrying `status` has found §4.2's named failure.
  static const taskFieldPriority       = 'taskField.priority';
  static const taskFieldPriorityUpdate = 'taskField.priority.update';
  static const taskFieldOwner          = 'taskField.owner';

  // ── Task List pane (Phase 3) ────────────────────────────────────────────
  static const taskListGroupHeaderPrefix = 'taskList.group.';   // + owner label
  static const taskListRowIndentPrefix   = 'taskList.rowIndent.'; // + task id
  static const taskListView              = 'taskList.view';
  static const taskListIncompleteBanner  = 'taskList.incompleteBanner';
  static const taskListEmptyState        = 'taskList.emptyState';
  static const taskListWriteNotice       = 'taskList.writeNotice';

  // ── Holding Area pane (Phase 4) ─────────────────────────────────────────
  //
  // Every per-group key is suffixed with the FILER at the use site, because the
  // blast radius of a batch control is one group and a test that cannot name which
  // group it pressed is a test that cannot prove the radius.
  static const holdingView                 = 'holding.view';
  static const holdingIncompleteBanner     = 'holding.incompleteBanner';
  static const holdingEmptyState           = 'holding.emptyState';
  static const holdingErrorView            = 'holding.error';
  static const holdingNotice               = 'holding.notice';
  static const holdingGroupHeaderPrefix    = 'holding.group.';           // + filer
  static const holdingApproveAllPrefix     = 'holding.approveAll.';      // + filer
  static const holdingWontFixAllPrefix     = 'holding.wontFixAll.';      // + filer
  static const holdingReasonFieldPrefix    = 'holding.reason.';          // + filer
  static const holdingReasonErrorPrefix    = 'holding.reasonError.';     // + filer
  static const holdingApproveAllConfirm    = 'holding.approveAll.confirm';
  static const holdingApproveAllConfirmOk  = 'holding.approveAll.confirm.ok';
  static const holdingApproveAllConfirmNo  = 'holding.approveAll.confirm.cancel';

  // ── Broadcast pane (Phase 5) ────────────────────────────────────────────
  //
  // 🔴 THE DISABLED REASON HAS ITS OWN KEY, AND THAT IS THE POINT OF THE SET. On the web
  // the reason Send is dead lives in `btn.title` — a tooltip, which a phone cannot show.
  // A key means a test can assert the operator could actually READ why nothing happens.
  static const broadcastView            = 'broadcast.view';
  static const broadcastBodyField       = 'broadcast.body';
  static const broadcastMicButton       = 'broadcast.mic';
  static const broadcastSendButton      = 'broadcast.send';
  static const broadcastDisabledReason  = 'broadcast.send.disabledReason';
  static const broadcastRecipientCount  = 'broadcast.recipients';
  static const broadcastRecipientRefresh = 'broadcast.recipients.refresh';
  static const broadcastMentionChips     = 'broadcast.mentions';
  static const broadcastMentionChipPrefix = 'broadcast.mention.';   // + persona name, or 'all'
  static const broadcastHistoryDisabled  = 'broadcast.history.disabled';
  static const broadcastHistoryEmpty     = 'broadcast.history.empty';
  static const broadcastHistoryRowPrefix = 'broadcast.history.';   // + index
  static const broadcastPreview         = 'broadcast.preview';
  static const broadcastSendConfirm     = 'broadcast.send.confirm';
  static const broadcastSendConfirmOk   = 'broadcast.send.confirm.ok';
  static const broadcastSendConfirmNo   = 'broadcast.send.confirm.cancel';
  static const broadcastNotice          = 'broadcast.notice';
  static const broadcastMicError        = 'broadcast.mic.error';

  /// 🔴 THE TALLY'S KEY, AND WHY IT IS NOT CALLED `broadcast.ackCount`.
  /// It is a SENTENCE, not a number, precisely because after the app stops listening
  /// there is no honest number to show — see [AckConfidence]. A key named for a count
  /// would invite the next hand to render one.
  static const broadcastAckSummary      = 'broadcast.ackSummary';
  static const broadcastAckRowPrefix    = 'broadcast.ack.';   // + session id

  // ── Home-screen cards for the fleet panes ───────────────────────────────
  //
  // 🔴 THESE KEYS EXIST SO "IS IT REACHABLE?" IS A TESTABLE QUESTION. Four panes
  // shipped green and unreachable because nothing anywhere asserted that a route to
  // them existed. A passing pane test says the pane works; it says nothing about
  // whether anyone can get to it.
  static const homeTaskListCard      = 'home.taskList';
  static const homeHoldingAreaCard   = 'home.holdingArea';
  static const homeFinishedTasksCard = 'home.finishedTasks';
  static const homeBroadcastCard     = 'home.broadcast';
}
