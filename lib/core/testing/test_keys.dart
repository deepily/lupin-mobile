/// Stable widget keys for UI tests (widget + integration + future Patrol/Maestro).
///
/// Production code attaches these via `Key( TestKeys.xxx )`; test code
/// looks them up via `find.byKey( Key( TestKeys.xxx ) )`. A single source
/// of truth prevents selector drift as UI copy/structure evolves and
/// survives i18n (unlike `find.text`).
class TestKeys {
  TestKeys._();

  // Login
  /// Key of the login email field.
  static const loginEmailField         = 'login.email';
  /// Key of the login password field.
  static const loginPasswordField      = 'login.password';
  /// Key of the login submit button.
  static const loginSubmitButton       = 'login.submit';
  /// Key of the login password visibility.
  static const loginPasswordVisibility = 'login.passwordVisibility';

  // Server switch (ServerContextToggle) — segments suffixed with the context
  // id from server-contexts.json, e.g. '${serverContextSegmentPrefix}lan-dev'
  /// Key of the server context toggle.
  static const serverContextToggle        = 'server_context.toggle';
  /// Key prefix of server context segment.
  static const serverContextSegmentPrefix = 'server_context.segment.';

  // Inbox — suffixed with senderId at use-site, e.g. '${inboxSenderTilePrefix}s-1'
  /// Key prefix of inbox sender tile.
  static const inboxSenderTilePrefix = 'inbox.sender.';

  // Conversation / InteractivePromptSheet
  /// Key prefix of conv respond button. The suffix is messageId.
  static const convRespondButtonPrefix = 'conv.respond.';
  /// Key of the conv summarize button.
  static const convSummarizeButton     = 'conv.summarize';
  /// Key of the conv dates button.
  static const convDatesButton         = 'conv.dates';
  /// Key of the conv gist sheet.
  static const convGistSheet           = 'conv.gistSheet';
  /// Key of the prompt yes button.
  static const promptYesButton         = 'prompt.yes';
  /// Key of the prompt no button.
  static const promptNoButton          = 'prompt.no';
  /// Key of the prompt neither button.
  static const promptNeitherButton     = 'prompt.neither';
  /// Key of the prompt comment field.
  static const promptCommentField      = 'prompt.comment';
  /// Submit button of the promoted multi-question body.
  static const promptMultiQuestionSubmit = 'prompt.multiQuestion.submit';
  // Dictate into the "Your response" box on a prompt card, appending rather than replacing.
  /// Key of the prompt response field.
  static const promptResponseField       = 'prompt.response';
  /// Key of the prompt response mic.
  static const promptResponseMic         = 'prompt.response.mic';
  /// Key of the prompt response mic cancel.
  static const promptResponseMicCancel   = 'prompt.response.mic.cancel';
  /// Key of the prompt response mic error.
  static const promptResponseMicError    = 'prompt.response.mic.error';

  // Sender-dates drilldown
  /// Key prefix of sender dates tile. The suffix is date.
  static const senderDatesTilePrefix          = 'senderDates.tile.';

  // Conversation by date
  /// Key prefix of conv by date section header. The suffix is date.
  static const convByDateSectionHeaderPrefix  = 'convByDate.section.';
  /// Key prefix of conv by date item. The suffix is notificationId.
  static const convByDateItemPrefix           = 'convByDate.item.';
  /// Key prefix of conv by date respond. The suffix is notificationId.
  static const convByDateRespondPrefix        = 'convByDate.respond.';

  // Trust Dashboard — per-decision actions
  /// Key prefix of trust decision card. The suffix is decisionId.
  static const trustDecisionCardPrefix = 'trust.decision.';
  /// Key prefix of trust decision approve. The suffix is decisionId.
  static const trustDecisionApprovePrefix = 'trust.decision.approve.';
  /// Key prefix of trust decision reject. The suffix is decisionId.
  static const trustDecisionRejectPrefix  = 'trust.decision.reject.';

  // Trust State drilldown (per-domain trust details)
  /// Key of the trust view details button.
  static const trustViewDetailsButton          = 'trust.viewDetails';
  /// Key prefix of trust state row. The suffix is '<domain>:<category>'.
  static const trustStateRowPrefix             = 'trust.state.row.';
  /// Key prefix of trust state domain header. The suffix is domain.
  static const trustStateDomainHeaderPrefix    = 'trust.state.domain.';

  // Abstract rendering + doc-link viewer
  /// Key of the abstract body.
  static const abstractBody         = 'docs.abstract.body';
  /// Key of the abstract open button, which opens the whole abstract.
  static const abstractOpenButton   = 'docs.abstract.open';
  /// Key of the doc viewer screen.
  static const docViewerScreen      = 'docs.viewer.screen';
  /// Key of the doc panel.
  static const docPanel             = 'docs.panel';
  /// Key of the doc split row.
  static const docSplitRow          = 'docs.split.row';
  /// Key of the doc split column.
  static const docSplitColumn       = 'docs.split.column';
  /// Key of the doc viewer markdown.
  static const docViewerMarkdown    = 'docs.viewer.markdown';
  /// Key of the doc viewer source.
  static const docViewerSource      = 'docs.viewer.source';
  /// Key of the doc viewer image.
  static const docViewerImage       = 'docs.viewer.image';
  /// Key of the doc viewer error.
  static const docViewerError       = 'docs.viewer.error';
  /// Key of the doc viewer share button.
  static const docViewerShareButton = 'docs.viewer.share';
  /// Key of the doc viewer close button.
  static const docViewerCloseButton = 'docs.viewer.close';
  /// Key of the doc viewer back button.
  static const docViewerBackButton     = 'docs.viewer.back';
  /// Key of the doc viewer download button.
  static const docViewerDownloadButton = 'docs.viewer.download';
  /// Key of the doc viewer folder button.
  static const docViewerFolderButton   = 'docs.viewer.folder';
  /// Key of the doc viewer no preview.
  static const docViewerNoPreview      = 'docs.viewer.noPreview';
  /// Key of the doc viewer upload button.
  static const docViewerUploadButton   = 'docs.viewer.upload';
  /// Key of the doc upload conflict sheet.
  static const docUploadConflictSheet  = 'docs.upload.conflictSheet';
  /// Key of the doc upload replace.
  static const docUploadReplace        = 'docs.upload.replace';
  /// Key of the doc upload rename.
  static const docUploadRename         = 'docs.upload.rename';
  /// Key of the doc upload cancel.
  static const docUploadCancel         = 'docs.upload.cancel';
  /// Key of the doc upload done.
  static const docUploadDone           = 'docs.upload.done';
  /// Key of the doc upload error.
  static const docUploadError          = 'docs.upload.error';
  /// Key of the doc listing.
  static const docListing              = 'docs.listing';
  /// Key of the doc listing up.
  static const docListingUp            = 'docs.listing.up';
  /// Key prefix of doc listing entry. The suffix is entry name.
  static const docListingEntryPrefix   = 'docs.listing.entry.';
  /// Key of the doc listing empty.
  static const docListingEmpty         = 'docs.listing.empty';
  /// Key of the doc roots panel.
  static const docRootsPanel           = 'docs.roots';
  /// Key of the focus files button, which opens the global file viewer.
  static const focusFilesButton        = 'focus.files';
  /// Key prefix of doc root. The suffix is scope/prefix.
  static const docRootPrefix           = 'docs.roots.root.';
  /// Key of the doc viewer placement toggle for a wide screen.
  ///
  /// It moves the viewer beside or below the conversation.
  static const docViewerPlacementToggle = 'docs.viewer.placement';
  /// Key prefix of doc dir entry. The suffix is entry name.
  static const docDirEntryPrefix    = 'docs.dir.entry.';

  // Deep research form
  /// Key of the dr query field.
  static const drQueryField     = 'dr.query';
  /// Key of the dr dry run checkbox.
  static const drDryRunCheckbox = 'dr.dryRun';
  /// Key of the dr submit button.
  static const drSubmitButton   = 'dr.submit';

  // Podcast generator form (pg = podcast generator)
  /// Key of the pg source field.
  static const pgSourceField    = 'pg.source';
  /// Key of the pg dry run switch.
  static const pgDryRunSwitch   = 'pg.dryRun';
  /// Key of the pg submit button.
  static const pgSubmitButton   = 'pg.submit';

  // Presentation generator form (px = presentation; avoids clash with pg)
  /// Key of the px source field.
  static const pxSourceField       = 'px.source';
  /// Key of the px render only switch.
  static const pxRenderOnlySwitch  = 'px.renderOnly';
  /// Key of the px dry run switch.
  static const pxDryRunSwitch      = 'px.dryRun';
  /// Key of the px submit button.
  static const pxSubmitButton      = 'px.submit';

  // SWE Team form
  /// Key of the sw task field.
  static const swTaskField      = 'sw.task';
  /// Key of the sw submit button.
  static const swSubmitButton   = 'sw.submit';

  // Bug Fix Expediter form
  /// Key of the bfe dead job id field.
  static const bfeDeadJobIdField = 'bfe.deadJobId';
  /// Key of the bfe dry run switch.
  static const bfeDryRunSwitch   = 'bfe.dryRun';
  /// Key of the bfe submit button.
  static const bfeSubmitButton   = 'bfe.submit';

  // Test Fix Expediter form (Resume-from flow)
  /// Key of the tfe resume from field.
  static const tfeResumeFromField = 'tfe.resumeFrom';
  /// Key of the tfe submit button.
  static const tfeSubmitButton    = 'tfe.submit';

  // Test Suite form (prefix suffixed with test type at use-site)
  /// Key prefix of ts test type checkbox. The suffix is testType name.
  static const tsTestTypeCheckboxPrefix = 'ts.type.';
  /// Key of the ts auto fix switch.
  static const tsAutoFixSwitch          = 'ts.autoFix';
  /// Key of the ts dry run switch.
  static const tsDryRunSwitch           = 'ts.dryRun';
  /// Key of the ts submit button.
  static const tsSubmitButton           = 'ts.submit';

  // Research → Podcast form (rp)
  /// Key of the rp query field.
  static const rpQueryField     = 'rp.query';
  /// Key of the rp dry run switch.
  static const rpDryRunSwitch   = 'rp.dryRun';
  /// Key of the rp submit button.
  static const rpSubmitButton   = 'rp.submit';

  // Research → Presentation form (rx)
  /// Key of the rx query field.
  static const rxQueryField     = 'rx.query';
  /// Key of the rx dry run switch.
  static const rxDryRunSwitch   = 'rx.dryRun';
  /// Key of the rx submit button.
  static const rxSubmitButton   = 'rx.submit';

  // Notification audio settings (six toggles)
  /// Key of the settings ding medium.
  static const settingsDingMedium   = 'settings.audio.dingMedium';
  /// Key of the settings ding high.
  static const settingsDingHigh     = 'settings.audio.dingHigh';
  /// Key of the settings ding urgent.
  static const settingsDingUrgent   = 'settings.audio.dingUrgent';
  /// Key of the settings speak high.
  static const settingsSpeakHigh    = 'settings.audio.speakHigh';
  /// Key of the settings speak urgent.
  static const settingsSpeakUrgent  = 'settings.audio.speakUrgent';
  /// Key of the settings master mute.
  static const settingsMasterMute   = 'settings.audio.masterMute';
  /// Key of the settings speak system.
  static const settingsSpeakSystem  = 'settings.audio.speakSystemSenders';
  /// Key of the settings wake notifications.
  static const settingsWakeNotifications = 'settings.audio.wakeNotifications';

  // Home screen AppBar
  /// Key of the home settings button.
  static const homeSettingsButton   = 'home.settings';
  /// Key of the home fleet status card.
  static const homeFleetStatusCard  = 'home.fleetStatus';
  /// Key of the home lupin focus card.
  static const homeLupinFocusCard   = 'home.lupinFocus';

  // Voice persona badge.
  // Used at every wiring site (inbox tile, conversation header, by-date item).
  // Suffix with senderId at use-site, e.g. '${personaBadgePrefix}s-1'.
  /// Key prefix of persona badge. The suffix is senderId.
  static const personaBadgePrefix       = 'persona.badge.';
  /// Key prefix of persona badge dashed. The suffix is senderId (borrowed variant).
  static const personaBadgeDashedPrefix = 'persona.badge.dashed.';
  /// Key prefix of the dotted persona badge, the overflow variant. The suffix is senderId.
  static const personaBadgeDottedPrefix = 'persona.badge.dotted.';

  // Focus-mode surface
  /// Key of the focus rail.
  static const focusRail            = 'focus.rail';
  /// Key prefix of focus rail badge. The suffix is senderId.
  static const focusRailBadgePrefix = 'focus.rail.badge.';
  /// Key of the focus pause toggle.
  static const focusPauseToggle     = 'focus.pauseToggle';
  /// Key of the focus chat pane.
  static const focusChatPane        = 'focus.chatPane';
  /// Key of the focus drawer button.
  static const focusDrawerButton    = 'focus.drawerButton';
  /// Key of the focus drawer logout.
  static const focusDrawerLogout    = 'focus.drawerLogout';
  // Focus drawer, surfaces experiment
  /// Key of the focus drawer header.
  static const focusDrawerHeader      = 'focus.drawerHeader';
  /// Key of the focus drawer build line.
  static const focusDrawerBuildLine   = 'focus.drawerBuildLine';
  /// Key prefix of focus drawer entry. The suffix is entry title.
  static const focusDrawerEntryPrefix = 'focus.drawerEntry.';
  /// Key of the focus composer scroll.
  static const focusComposerScroll  = 'focus.composerScroll';
  /// Key of the focus paused banner.
  static const focusPausedBanner    = 'focus.pausedBanner';
  /// Key of the focus retry banner.
  static const focusRetryBanner     = 'focus.retryBanner';
  /// Key prefix of focus batch fallback. The suffix is notificationId.
  static const focusBatchFallbackPrefix = 'focus.batchFallback.';
  /// Key prefix of focus bubble. The suffix is notificationId.
  static const focusBubblePrefix        = 'focus.bubble.';
  // Long-press mute shortcut
  /// Key of the sender mute action.
  static const senderMuteAction         = 'sender.mute.action';
  /// Key of the sender unmute action.
  static const senderUnmuteAction       = 'sender.unmute.action';
  /// Key of the sender mute undo.
  static const senderMuteUndo           = 'sender.mute.undo';
  /// Key of the focus header persona name.
  static const focusHeaderPersonaName   = 'focus.header.personaName';
  /// Key of the focus header sender id.
  static const focusHeaderSenderId      = 'focus.header.senderId';
  // Focus rail visibility lens
  /// Key of the focus filter bar.
  static const focusFilterBar            = 'focus.filterBar';
  /// Key of the focus filter live.
  static const focusFilterLive           = 'focus.filter.live';
  /// Key of the focus filter history.
  static const focusFilterHistory        = 'focus.filter.history';
  /// Key of the focus scope personas.
  static const focusScopePersonas        = 'focus.scope.personas';
  /// Key of the focus scope all.
  static const focusScopeAll             = 'focus.scope.all';
  /// Key of the focus rail group divider.
  static const focusRailGroupDivider     = 'focus.rail.groupDivider';
  /// Key of the focus composer caption.
  static const focusComposerCaption      = 'focus.composer.caption';
  /// Key of the focus queue button.
  static const focusQueueButton          = 'focus.queueButton';
  /// Key of the focus roster refresh button.
  static const focusRosterRefreshButton  = 'focus.rosterRefreshButton';
  /// Key of the resend control for an unsent focus message.
  static const focusUnsentResend         = 'focus.unsent.resend';
  /// Key of the focus unsent closed.
  static const focusUnsentClosed         = 'focus.unsent.closed';
  /// Key of the focus queue badge.
  static const focusQueueBadge           = 'focus.queueButton.badge';
  /// Key of the tts queue sheet.
  static const ttsQueueSheet             = 'ttsQueue.sheet';
  /// Key of the tts queue empty.
  static const ttsQueueEmpty             = 'ttsQueue.empty';
  /// Key of the tts queue skip.
  static const ttsQueueSkip              = 'ttsQueue.skip';
  /// Key of the tts queue clear.
  static const ttsQueueClear             = 'ttsQueue.clear';
  /// Key of the tts queue stop all.
  static const ttsQueueStopAll           = 'ttsQueue.stopAll';
  /// Key prefix of tts queue row. The suffix is item id.
  static const ttsQueueRowPrefix         = 'ttsQueue.row.';
  /// Key prefix of tts queue delete. The suffix is item id.
  static const ttsQueueDeletePrefix      = 'ttsQueue.delete.';
  /// Key prefix of focus rail status dot. The suffix is senderId.
  static const focusRailStatusDotPrefix  = 'focus.rail.dot.';
  /// Key prefix of focus rail initial. The suffix is senderId (fallback avatar).
  static const focusRailInitialPrefix    = 'focus.rail.initial.';
  /// Key of the focus rail empty hint.
  static const focusRailEmptyHint        = 'focus.rail.emptyHint';
  /// Key of the focus rail empty hint button.
  static const focusRailEmptyHintButton  = 'focus.rail.emptyHint.button';
  // Notification stop-list
  /// Key of the focus hidden caption.
  static const focusHiddenCaption            = 'focus.hiddenCaption';
  /// Key of the conversation hidden chip.
  static const conversationHiddenChip        = 'conversation.hiddenChip';
  /// Key of the settings open stop list.
  static const settingsOpenStopList          = 'settings.audio.openStopList';
  /// Key of the settings stop list add field.
  static const settingsStopListAddField      = 'settings.stopList.addField';
  /// Key of the settings stop list add button.
  static const settingsStopListAddButton     = 'settings.stopList.addButton';
  /// Key of the settings stop list menu.
  static const settingsStopListMenu          = 'settings.stopList.menu';
  /// Key of the settings stop list reset.
  static const settingsStopListReset         = 'settings.stopList.reset';
  /// Key prefix of settings stop list row. The suffix is pattern.
  static const settingsStopListRowPrefix     = 'settings.stopList.row.';
  /// Key prefix of settings stop list toggle. The suffix is pattern.
  static const settingsStopListTogglePrefix  = 'settings.stopList.toggle.';
  // Notification management view
  /// Key of the settings open notification management.
  static const settingsOpenNotificationManagement = 'settings.openNotificationManagement';
  /// Key of the notif mgmt master.
  static const notifMgmtMaster               = 'notifMgmt.master';
  /// Key of the notif mgmt background.
  static const notifMgmtBackground           = 'notifMgmt.background';
  /// Key of the notif mgmt foreground.
  static const notifMgmtForeground           = 'notifMgmt.foreground';
  /// Key prefix of one priority checkbox.
  ///
  /// The suffix is `<surface>.<priority>`, e.g. `notifMgmt.priority.background.urgent`.
  static const notifMgmtPriorityPrefix       = 'notifMgmt.priority.';
  /// Key of the notif mgmt open sound.
  static const notifMgmtOpenSound            = 'notifMgmt.openSound';
  /// Key of the notif mgmt open stop list.
  static const notifMgmtOpenStopList         = 'notifMgmt.openStopList';
  /// Key of the priority checkbox for [surface] and [priority].
  static String notifMgmtPriority( String surface, String priority ) =>
      '$notifMgmtPriorityPrefix$surface.$priority';
  // Mute by sender and quiet hours
  /// Key of the notif mgmt mute add.
  static const notifMgmtMuteAdd              = 'notifMgmt.mute.add';
  /// Key prefix of notif mgmt mute row. The suffix is sender key.
  static const notifMgmtMuteRowPrefix        = 'notifMgmt.mute.row.';
  /// Key prefix of notif mgmt mute remove. The suffix is sender key.
  static const notifMgmtMuteRemovePrefix     = 'notifMgmt.mute.remove.';
  /// Key prefix of notif mgmt mute pick. The suffix is sender key.
  static const notifMgmtMutePickPrefix       = 'notifMgmt.mute.pick.';
  /// Key of the notif mgmt mute urgent bypass.
  static const notifMgmtMuteUrgentBypass     = 'notifMgmt.mute.urgentBypass';
  /// Key of the notif mgmt quiet.
  static const notifMgmtQuiet                = 'notifMgmt.quiet';
  /// Key of the notif mgmt quiet start.
  static const notifMgmtQuietStart           = 'notifMgmt.quiet.start';
  /// Key of the notif mgmt quiet end.
  static const notifMgmtQuietEnd             = 'notifMgmt.quiet.end';
  /// Key of the notif mgmt quiet urgent bypass.
  static const notifMgmtQuietUrgentBypass    = 'notifMgmt.quiet.urgentBypass';

  /// Key of the push pause status.
  static const pushPauseStatus               = 'pushPause.status';
  /// Key of the push pause admin only.
  static const pushPauseAdminOnly            = 'pushPause.adminOnly';
  /// Key of the push pause error.
  static const pushPauseError                = 'pushPause.error';
  /// Key of the push pause resume.
  static const pushPauseResume               = 'pushPause.resume';
  /// Key of the push-pause duration choice for [minutes].
  ///
  /// A null [minutes] gives the `open` choice, the "until I resume" chip.
  static String pushPauseDuration( int? minutes ) => 'pushPause.duration.${minutes ?? 'open'}';

  /// Key of the heartbeat poke switch.
  static const heartbeatPokeSwitch           = 'heartbeatPoke.switch';
  /// Key of the heartbeat poke status.
  static const heartbeatPokeStatus           = 'heartbeatPoke.status';
  /// Key of the heartbeat poke admin only.
  static const heartbeatPokeAdminOnly        = 'heartbeatPoke.adminOnly';
  /// Key of the heartbeat poke error.
  static const heartbeatPokeError            = 'heartbeatPoke.error';

  // A visible delete with undo, and tap-to-edit
  /// Key prefix of settings stop list delete. The suffix is pattern.
  static const settingsStopListDeletePrefix  = 'settings.stopList.delete.';
  /// Key of the settings stop list edit field.
  static const settingsStopListEditField     = 'settings.stopList.edit.field';
  /// Key of the settings stop list edit save.
  static const settingsStopListEditSave      = 'settings.stopList.edit.save';
  /// Key of the settings stop list edit cancel.
  static const settingsStopListEditCancel    = 'settings.stopList.edit.cancel';
  // Debug: network round-trip probe
  /// Key of the settings open round trip probe.
  static const settingsOpenRoundTripProbe    = 'settings.debug.openRoundTripProbe';
  // Debug: keep voice recordings as WAV
  /// Key of the settings keep voice recordings.
  static const settingsKeepVoiceRecordings   = 'settings.debug.keepVoiceRecordings';
  /// Key of the probe run button.
  static const probeRunButton                = 'probe.run';
  /// Key of the probe copy path button.
  static const probeCopyPathButton           = 'probe.copyPath';
  /// Key of the probe progress.
  static const probeProgress                 = 'probe.progress';
  // TTS preview-fraction slider pinned at the top of the focus pane
  /// Key of the focus tts fraction bar.
  static const focusTtsFractionBar             = 'focus.ttsFraction.bar';
  /// Key of the focus tts fraction slider.
  static const focusTtsFractionSlider          = 'focus.ttsFraction.slider';
  /// Key of the focus tts fraction value.
  static const focusTtsFractionValue           = 'focus.ttsFraction.value';
  // Lower-left timestamp on every notification bubble or card
  /// Key prefix of message stamp. The suffix is notification id.
  static const messageStampPrefix              = 'message.stamp.';
  // Progress-group collapse
  /// Key of the settings collapse groups.
  static const settingsCollapseGroups          = 'settings.collapseGroups';
  /// Key prefix of focus group. The suffix is groupKey-latestId.
  static const focusGroupPrefix                = 'focus.group.';
  /// Key prefix of focus group toggle. The suffix is Key(...).toString().
  static const focusGroupTogglePrefix          = 'focus.group.toggle.';
  /// Key prefix of conversation group. The suffix is groupKey-latestId.
  static const conversationGroupPrefix         = 'conversation.group.';
  /// Key prefix of conversation group toggle. The suffix is Key(...).toString().
  static const conversationGroupTogglePrefix   = 'conversation.group.toggle.';

  // Focus-mode voice reply composer
  /// Key of the voice reply mic.
  static const voiceReplyMic        = 'voiceReply.mic';
  /// Key of the voice reply edit control, for typing instead of dictating.
  static const voiceReplyEdit       = 'voiceReply.edit';
  /// Key of the voice reply idle row.
  static const voiceReplyIdleRow    = 'voiceReply.idleRow';
  /// Key of the voice reply transcript.
  static const voiceReplyTranscript = 'voiceReply.transcript';
  /// Key of the voice reply send.
  static const voiceReplySend       = 'voiceReply.send';
  /// Key of the voice reply cancel.
  static const voiceReplyCancel     = 'voiceReply.cancel';
  /// Key of the voice reply error affordance.
  static const voiceReplyError      = 'voiceReply.error';
  // Dictate another chunk into the open editor box.
  // The words are appended at the caret, never replacing what is already there.
  /// Key of the voice reply append mic.
  static const voiceReplyAppendMic    = 'voiceReply.appendMic';
  /// Key of the voice reply append cancel.
  static const voiceReplyAppendCancel = 'voiceReply.appendCancel';

  // Audio artifact player: in-app playback for pg-* and rp- jobs
  /// Key of the audio player download button.
  static const audioPlayerDownloadButton = 'audio.download';
  /// Key of the audio player play button.
  static const audioPlayerPlayButton     = 'audio.play';
  /// Key of the audio player pause button.
  static const audioPlayerPauseButton    = 'audio.pause';
  /// Key of the audio player stop button.
  static const audioPlayerStopButton     = 'audio.stop';
  /// Key of the audio player share button.
  static const audioPlayerShareButton    = 'audio.share';
  /// Key of the audio player slider.
  static const audioPlayerSlider         = 'audio.slider';

  // ── Quick Ask ──
  /// Key of the quick ask record button.
  static const quickAskRecordButton   = 'quickAsk.record';
  /// Key of the quick ask send mode toggle.
  static const quickAskSendModeToggle = 'quickAsk.sendMode';
  /// Key of the quick ask clear button.
  static const quickAskClearButton    = 'quickAsk.clear';
  /// Key of the quick ask send button.
  static const quickAskSendButton     = 'quickAsk.send';
  /// Key of the quick ask draft text.
  static const quickAskDraftText      = 'quickAsk.draft';
  /// Key of the quick ask blocked reason.
  static const quickAskBlockedReason  = 'quickAsk.blockedReason';
  /// Key of the quick ask error.
  static const quickAskError          = 'quickAsk.error';
  /// Key of the quick ask list.
  static const quickAskList           = 'quickAsk.list';
  /// Key of the quick ask empty.
  static const quickAskEmpty          = 'quickAsk.empty';
  /// Key of the quick ask lost banner.
  static const quickAskLostBanner     = 'quickAsk.lost';
  /// Key prefix of quick ask card. The suffix is jobId.
  static const quickAskCardPrefix     = 'quickAsk.card.';
  /// Key prefix of quick ask card dismiss. The suffix is jobId.
  static const quickAskCardDismissPrefix = 'quickAsk.card.dismiss.';
  /// Key prefix of quick ask chip. The suffix is lane name.
  static const quickAskChipPrefix     = 'quickAsk.chip.';
  /// Key prefix of quick ask answer. The suffix is jobId.
  static const quickAskAnswerPrefix   = 'quickAsk.answer.';
  /// Key prefix of quick ask error card. The suffix is jobId.
  static const quickAskErrorCardPrefix = 'quickAsk.errorCard.';
  /// Key prefix of quick ask progress. The suffix is jobId.
  static const quickAskProgressPrefix = 'quickAsk.progress.';
  /// Key of the quick ask pause toggle.
  static const quickAskPauseToggle    = 'quickAsk.pauseToggle';
  /// Key of the quick ask paused banner.
  static const quickAskPausedBanner   = 'quickAsk.pausedBanner';
  /// Key prefix of quick ask replay. The suffix is jobId.
  static const quickAskReplayPrefix   = 'quickAsk.replay.';
  /// Key of the quick ask interview.
  static const quickAskInterview      = 'quickAsk.interview';
  /// Key of the quick ask interview q.
  static const quickAskInterviewQ     = 'quickAsk.interview.question';
  /// Key of the quick ask interview cancel.
  static const quickAskInterviewCancel= 'quickAsk.interview.cancel';
  /// Key of the quick ask needs input card.
  static const quickAskNeedsInputCard = 'quickAsk.needsInput';
  // The Door C interlock surface, live while an ask is in flight.
  /// Key of the quick ask prompt.
  static const quickAskPrompt         = 'quickAsk.prompt';
  /// Key of the quick ask prompt question.
  static const quickAskPromptQuestion = 'quickAsk.prompt.question';
  /// Key of the quick ask prompt dismiss.
  static const quickAskPromptDismiss  = 'quickAsk.prompt.dismiss';

  // ── Suppressed-question notice ──
  /// Key of the prompt suppressed notice.
  static const promptSuppressedNotice = 'prompt.suppressed.notice';
  /// Key of the prompt suppressed rule.
  static const promptSuppressedRule   = 'prompt.suppressed.rule';
  /// Key of the prompt speak anyway.
  static const promptSpeakAnyway      = 'prompt.suppressed.speakAnyway';

  // ── Finished Tasks pane ──
  // The row cell keys are suffixed with the event id at the use site, so a test
  // can assert the four cells of one identified row rather than counting widgets.
  /// Key of the finished refresh button.
  static const finishedRefreshButton    = 'finished.refresh';
  /// Key prefix of finished status pill. The suffix is status.
  static const finishedStatusPillPrefix = 'finished.pill.';
  /// Key of the finished window slider.
  static const finishedWindowSlider     = 'finished.window.slider';
  /// Key of the finished window label.
  static const finishedWindowLabel      = 'finished.window.label';
  /// Key of the finished partial banner.
  static const finishedPartialBanner    = 'finished.partialBanner';
  /// Key of the finished empty state.
  static const finishedEmptyState       = 'finished.empty';
  /// Key of the finished error view.
  static const finishedErrorView        = 'finished.error';
  /// Key prefix of finished row glyph. The suffix is event id.
  static const finishedRowGlyphPrefix   = 'finished.row.glyph.';
  /// Key prefix of finished row when. The suffix is event id.
  static const finishedRowWhenPrefix    = 'finished.row.when.';
  /// Key prefix of finished row title. The suffix is event id.
  static const finishedRowTitlePrefix   = 'finished.row.title.';
  /// Key prefix of finished row who. The suffix is event id.
  static const finishedRowWhoPrefix     = 'finished.row.who.';
  /// Key prefix of finished row why. The suffix is event id.
  static const finishedRowWhyPrefix     = 'finished.row.why.';
  // ── Fleet Status pane ──
  /// Key of the fleet status list.
  static const fleetStatusList        = 'fleetStatus.list';
  /// Key of the fleet status offline toggle.
  static const fleetStatusOfflineToggle = 'fleetStatus.offlineToggle';
  /// Suffixed with the row's session id, e.g. `${fleetStatusRowPrefix}<session id>`.
  static const fleetStatusRowPrefix   = 'fleetStatus.row.';
  /// The Liveness cell, a tap target here because a phone has no hover.
  static const fleetStatusLivenessPrefix = 'fleetStatus.liveness.';
  /// Key of the fleet status liveness sheet.
  static const fleetStatusLivenessSheet  = 'fleetStatus.livenessSheet';

  /// The watch-console button on a fleet row, suffixed with the row's Who label.
  ///
  /// The suffix is the one [fleetStatusRowPrefix] and [fleetStatusLivenessPrefix] use, so a test that has a row has its button.
  /// It is a separate key because it is a separate hit target. It must not be reachable through the liveness key.
  /// The tap test asserts the watch button does not fire `onLivenessTap`. Two widgets sharing a key would make that unprovable.
  static const fleetStatusWatchPrefix    = 'fleetStatus.watch.';

  // --- Live Console: the Claude Code transcript stream ---
  /// Key of the live console screen.
  static const liveConsoleScreen        = 'liveConsole.screen';
  /// Key of the live console session id.
  static const liveConsoleSessionId     = 'liveConsole.sessionId';
  /// Key of the live console list.
  static const liveConsoleList          = 'liveConsole.list';
  /// Key of the live console spinner.
  static const liveConsoleSpinner       = 'liveConsole.spinner';
  /// Key of the live console error.
  static const liveConsoleError         = 'liveConsole.error';
  /// Key of the live console jump to live.
  static const liveConsoleJumpToLive    = 'liveConsole.jumpToLive';
  /// Key of the live console load earlier.
  static const liveConsoleLoadEarlier   = 'liveConsole.loadEarlier';
  /// Key of the live console refused.
  static const liveConsoleRefused       = 'liveConsole.refused';
  /// Key of the live console refused reason.
  static const liveConsoleRefusedReason = 'liveConsole.refusedReason';
  /// Key of the live console back.
  static const liveConsoleBack          = 'liveConsole.back';

  /// Assistant prose; the only block key that belongs to a markdown widget.
  ///
  /// A test asserts tool output has no `Markdown` ancestor, so the two families of key must not overlap.
  static const transcriptProse          = 'transcript.prose';

  /// A collapsible block's header, suffixed with the wire kind.
  ///
  /// The kinds are `tool_call`, `tool_result`, `thinking` and `unknown`.
  static const transcriptChipPrefix     = 'transcript.chip.';

  /// A collapsible block's expanded monospace body, same suffixes.
  static const transcriptPlainPrefix    = 'transcript.plain.';

  /// A `thinking` block the server sent with no text: a dim, non-expandable label.
  static const transcriptUnrecordedThinking = 'transcript.unrecorded.thinking';

  /// Key of the transcript truncated marker.
  static const transcriptTruncatedMarker = 'transcript.truncated';
  /// Key of the unreachable state, distinct from the empty state.
  ///
  /// The server answers `status: "unreachable"` with an HTTP 200.
  /// So "we cannot see the fleet" and "the fleet has no seats" must be two different things on screen.
  static const fleetStatusUnreachable = 'fleetStatus.unreachable';
  /// Key of the fleet status empty.
  static const fleetStatusEmpty       = 'fleetStatus.empty';
  // The fleet-size cap dial — a real write, PUT /api/arbiter/fleet-size-cap.
  /// Key of the fleet status cap dial.
  static const fleetStatusCapDial     = 'fleetStatus.capDial';
  /// Key of the fleet status cap value.
  static const fleetStatusCapValue    = 'fleetStatus.capValue';
  /// Key of the fleet status cap apply.
  static const fleetStatusCapApply    = 'fleetStatus.capApply';

  // ── Fleet panes: the shared task row ──
  //
  // The cell prefix is the cell-identity guard's only handle.
  // `find.byType( TaskRow )` passes while the two panes drift four different ways: a `pane:` parameter
  // branching inside, different field subsets, a bespoke row for a special case, or a wrapper.
  // Selecting the ordered cell keys catches all four, because it compares what was actually rendered
  // rather than which class rendered it.
  /// Key prefix of task row cell. The suffix is RowCell.key.
  static const taskRowCellPrefix    = 'taskRow.cell.';
  /// Key of the task row disclosure.
  static const taskRowDisclosure    = 'taskRow.disclosure';
  /// Key of the task row controls.
  static const taskRowControls      = 'taskRow.controls';
  /// Key prefix of task row verb. The suffix is verb name.
  static const taskRowVerbPrefix    = 'taskRow.verb.';

  // The unsent mark sits on the row, not in a notice bar. A bar says 'something
  // failed' while the operator is looking at fifty rows, and the question they are
  // asking is whether their write landed.
  /// Key of the task row unsent mark.
  static const taskRowUnsentMark    = 'taskRow.unsentMark';

  // ── The shared verb reason sheet ──
  //
  // No key here has a pane segment, on purpose. The sheet takes no pane parameter,
  // so a key like `reasonSheet.taskList.reason` could only come from a sheet that had grown one.
  // A test naming a pane here would make that drift look intentional.
  /// Key of the reason sheet.
  static const reasonSheet          = 'reasonSheet';
  /// Key of the reason sheet reason.
  static const reasonSheetReason    = 'reasonSheet.reason';
  /// Key of the reason sheet date.
  static const reasonSheetDate      = 'reasonSheet.date';
  /// Key of the reason sheet date error.
  static const reasonSheetDateError = 'reasonSheet.dateError';
  /// Key of the reason sheet submit.
  static const reasonSheetSubmit    = 'reasonSheet.submit';
  /// Key of the reason sheet cancel.
  static const reasonSheetCancel    = 'reasonSheet.cancel';
  /// Key of the reason sheet no reason.
  static const reasonSheetNoReason  = 'reasonSheet.noReasonNotice';

  // ── The shared field-door controls ──
  //
  // Named for the door, not for the pane. These two keys are the field door:
  // the PATCH that may carry `priority` and `owner_persona` and nothing else.
  // A test that finds `taskField.*` on a request carrying `status` has found a named failure.
  /// Key of the task field priority.
  static const taskFieldPriority       = 'taskField.priority';
  /// Key of the task field priority update.
  static const taskFieldPriorityUpdate = 'taskField.priority.update';
  /// Key of the task field owner.
  static const taskFieldOwner          = 'taskField.owner';

  // ── Task List pane ──
  /// Key prefix of task list group header. The suffix is owner label.
  static const taskListGroupHeaderPrefix = 'taskList.group.';
  /// Key prefix of task list row indent. The suffix is task id.
  static const taskListRowIndentPrefix   = 'taskList.rowIndent.';
  /// Key of the task list view.
  static const taskListView              = 'taskList.view';
  /// Key of the task list incomplete banner.
  static const taskListIncompleteBanner  = 'taskList.incompleteBanner';
  /// Key of the task list empty state.
  static const taskListEmptyState        = 'taskList.emptyState';
  /// Key of the task list write notice.
  static const taskListWriteNotice       = 'taskList.writeNotice';
  /// Key of the task list count headline.
  static const taskListCountHeadline     = 'taskList.countHeadline';
  /// Key of the task list new task.
  static const taskListNewTask           = 'taskList.newTask';
  /// Key of the new ticket sheet.
  static const newTicketSheet            = 'newTicket.sheet';
  /// Key of the new ticket title.
  static const newTicketTitle            = 'newTicket.title';
  /// Key of the new ticket details.
  static const newTicketDetails          = 'newTicket.details';
  /// Key of the new ticket owner.
  static const newTicketOwner            = 'newTicket.owner';
  /// Key of the new ticket manager.
  static const newTicketManager          = 'newTicket.manager';
  /// Key of the new ticket priority.
  static const newTicketPriority         = 'newTicket.priority';
  /// Key of the new ticket approved.
  static const newTicketApproved         = 'newTicket.approved';
  /// Key of the new ticket type.
  static const newTicketType             = 'newTicket.type';
  /// Key of the new ticket epic.
  static const newTicketEpic             = 'newTicket.epic';
  /// Key of the new ticket project.
  static const newTicketProject          = 'newTicket.project';
  /// Key of the new ticket title mic.
  static const newTicketTitleMic         = 'newTicket.titleMic';
  /// Key of the new ticket details mic.
  static const newTicketDetailsMic       = 'newTicket.detailsMic';
  /// Key of the new ticket result.
  static const newTicketResult           = 'newTicket.result';
  /// Key of the new ticket create.
  static const newTicketCreate           = 'newTicket.create';
  /// Key of the new ticket cancel.
  static const newTicketCancel           = 'newTicket.cancel';
  /// Key of the task lookup input.
  static const taskLookupInput           = 'taskList.lookup.input';
  /// Key of the task lookup go.
  static const taskLookupGo              = 'taskList.lookup.go';
  /// Key of the task lookup clear.
  static const taskLookupClear           = 'taskList.lookup.clear';
  /// Key of the task lookup message.
  static const taskLookupMessage         = 'taskList.lookup.message';
  /// Key of the task lookup result card.
  static const taskLookupResultCard      = 'taskList.lookup.resultCard';
  /// Key of the task lookup result status.
  static const taskLookupResultStatus    = 'taskList.lookup.resultStatus';

  // ── Holding Area pane ──
  //
  // Every per-group key is suffixed with the filer at the use site. The blast radius of a batch
  // control is one group, and a test that cannot name which group it pressed cannot prove the radius.
  /// Key of the holding view.
  static const holdingView                 = 'holding.view';
  /// Key of the holding incomplete banner.
  static const holdingIncompleteBanner     = 'holding.incompleteBanner';
  /// Key of the holding empty state.
  static const holdingEmptyState           = 'holding.emptyState';
  /// Key of the holding error view.
  static const holdingErrorView            = 'holding.error';
  /// Key of the holding notice.
  static const holdingNotice               = 'holding.notice';
  /// Key prefix of holding group header. The suffix is filer.
  static const holdingGroupHeaderPrefix    = 'holding.group.';
  /// Key prefix of holding group toggle. The suffix is filer.
  static const holdingGroupTogglePrefix    = 'holding.group.toggle.';
  /// Key prefix of holding approve all. The suffix is filer.
  static const holdingApproveAllPrefix     = 'holding.approveAll.';
  /// Key prefix of holding wont fix all. The suffix is filer.
  static const holdingWontFixAllPrefix     = 'holding.wontFixAll.';
  /// Key prefix of holding reason field. The suffix is filer.
  static const holdingReasonFieldPrefix    = 'holding.reason.';
  /// Key prefix of holding reason error. The suffix is filer.
  static const holdingReasonErrorPrefix    = 'holding.reasonError.';
  /// Key of the holding approve all confirm.
  static const holdingApproveAllConfirm    = 'holding.approveAll.confirm';
  /// Key of the holding approve all confirm ok.
  static const holdingApproveAllConfirmOk  = 'holding.approveAll.confirm.ok';
  /// Key of the holding approve all confirm no.
  static const holdingApproveAllConfirmNo  = 'holding.approveAll.confirm.cancel';

  // ── Broadcast pane ──
  //
  // The disabled reason has its own key. On the web the reason Send is dead lives in `btn.title`,
  // a tooltip, which a phone cannot show. A key means a test can assert the operator could read why nothing happens.
  /// Key of the broadcast view.
  static const broadcastView            = 'broadcast.view';
  /// Key of the broadcast body field.
  static const broadcastBodyField       = 'broadcast.body';
  /// Key of the broadcast mic button.
  static const broadcastMicButton       = 'broadcast.mic';
  /// Key of the broadcast send button.
  static const broadcastSendButton      = 'broadcast.send';
  /// Key of the broadcast disabled reason.
  static const broadcastDisabledReason  = 'broadcast.send.disabledReason';
  /// Key of the broadcast recipient count.
  static const broadcastRecipientCount  = 'broadcast.recipients';
  /// Key of the broadcast recipient refresh.
  static const broadcastRecipientRefresh = 'broadcast.recipients.refresh';
  /// Key of the broadcast mention chips.
  static const broadcastMentionChips     = 'broadcast.mentions';
  /// Key prefix of broadcast mention chip. The suffix is persona name, or 'all'.
  static const broadcastMentionChipPrefix = 'broadcast.mention.';
  /// Key of the broadcast history disabled.
  static const broadcastHistoryDisabled  = 'broadcast.history.disabled';
  /// Key of the broadcast history empty.
  static const broadcastHistoryEmpty     = 'broadcast.history.empty';
  /// Key prefix of broadcast history row. The suffix is index.
  static const broadcastHistoryRowPrefix = 'broadcast.history.';
  /// Key of the broadcast preview.
  static const broadcastPreview         = 'broadcast.preview';
  /// Key of the broadcast send confirm.
  static const broadcastSendConfirm     = 'broadcast.send.confirm';
  /// Key of the broadcast send confirm ok.
  static const broadcastSendConfirmOk   = 'broadcast.send.confirm.ok';
  /// Key of the broadcast send confirm no.
  static const broadcastSendConfirmNo   = 'broadcast.send.confirm.cancel';
  /// Key of the broadcast notice.
  static const broadcastNotice          = 'broadcast.notice';
  /// Key of the broadcast mic error.
  static const broadcastMicError        = 'broadcast.mic.error';

  /// Key of the acknowledgement tally, which is a sentence and not a number.
  ///
  /// After the app stops listening there is no honest number to show (see [AckConfidence]).
  /// A key named for a count would invite the next hand to render one, hence it is not `broadcast.ackCount`.
  static const broadcastAckSummary      = 'broadcast.ackSummary';
  /// Key prefix of broadcast ack row. The suffix is session id.
  static const broadcastAckRowPrefix    = 'broadcast.ack.';

  // ── Home-screen cards for the fleet panes ──
  //
  // These keys exist so that "is it reachable?" is a testable question.
  // Four panes shipped green and unreachable because nothing asserted that a route to them existed.
  // A passing pane test says the pane works; it says nothing about whether anyone can get to it.
  /// Key of the home task list card.
  static const homeTaskListCard      = 'home.taskList';
  /// Key of the home holding area card.
  static const homeHoldingAreaCard   = 'home.holdingArea';
  /// Key of the home finished tasks card.
  static const homeFinishedTasksCard = 'home.finishedTasks';
  /// Key of the home broadcast card.
  static const homeBroadcastCard     = 'home.broadcast';
}
