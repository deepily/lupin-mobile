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
  static const promptCommentField      = 'prompt.comment';

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

  // Home screen AppBar
  static const homeSettingsButton   = 'home.settings';

  // Voice persona badge (Phase 3 — voice-persona milestone)
  // Used at every wiring site (inbox tile, conversation header, by-date item).
  // Suffix with senderId at use-site, e.g. '${personaBadgePrefix}s-1'.
  static const personaBadgePrefix       = 'persona.badge.';        // + senderId
  static const personaBadgeDashedPrefix = 'persona.badge.dashed.'; // + senderId (borrowed variant)

  // Audio artifact player (Phase 4a — in-app playback for pg-* / rp- jobs)
  static const audioPlayerDownloadButton = 'audio.download';
  static const audioPlayerPlayButton     = 'audio.play';
  static const audioPlayerPauseButton    = 'audio.pause';
  static const audioPlayerStopButton     = 'audio.stop';
  static const audioPlayerShareButton    = 'audio.share';
  static const audioPlayerSlider         = 'audio.slider';
}
