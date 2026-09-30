# Lupin Mobile

A sophisticated Android mobile client for the Lupin AI assistant system, featuring voice interaction, real-time communication, and offline capabilities.

## 🚀 Project Status

**Lupin v0.1.6 Resync — All 4 Tiers Complete** ✅ — On-device validation pending

### What's New (2026-04-16 — v0.1.6 Resync)
- ✅ **Tier 1 — Auth**: Real JWT auth, biometric unlock, WS persistence, Dev/Test toggle
- ✅ **Tier 2 — Notifications + Decision Proxy**: InboxScreen, ConversationScreen, InteractivePromptSheet, TrustDashboardScreen, NotificationBloc, DecisionProxyBloc
- ✅ **Tier 3 — Queue/CJ Flow + Claude Code**: QueueDashboardScreen, JobDetailScreen, SubmitJobSheet, ChatScreen, SessionListScreen, DispatchSheet, QueueBloc, ClaudeCodeBloc
- ✅ **Tier 4 — Agentic Jobs**: AgenticHubScreen + 9 submission forms, AgenticRepository (10 endpoints), AgenticSubmissionBloc, IoFileService, MarkdownReportViewer, AudioArtifactPlayer, SlideDeckViewer
- ✅ **Tests**: 140/140 unit tests passing

### Current Capabilities
- **Authentication**: JWT login, biometric unlock, WS session persistence
- **Notifications / Decision Proxy**: Real-time inbox, interactive prompts, trust dashboard
- **Queue / CJ Flow**: Live job queue, job detail with WS progress, Claude Code chat sessions
- **Agentic Jobs**: Deep Research, Podcast, Presentation, SWE Team, Test Suite, chained R→Podcast/R→Presentation, Bug Fix Expediter, Test Fix Expediter submission forms
- **Artifact Viewers**: Markdown report viewer, audio artifact player, slide deck viewer
- **WebSocket**: Full WS bridge routing queue/CC events to BLoCs

## Architecture

### Technology Stack
- **Framework**: Flutter (Dart) with BLoC architecture
- **Backend**: FastAPI server integration (Lupin ecosystem)
- **TTS Providers**: ElevenLabs Flash v2.5 (primary), OpenAI TTS-1 (fallback)
- **Communication**: WebSocket for real-time streaming, HTTP for API calls
- **Authentication**: Session-based WebSocket authentication

### Key Components
- **TTS Service**: Provider abstraction layer supporting multiple TTS services
- **WebSocket Service**: Session management and real-time communication
- **BLoC Architecture**: State management for auth, queue, and notifications
- **Test UI**: Comprehensive validation interface for TTS streaming

## Development Workflow

**Hybrid Development Approach**:
1. **Code Generation**: Claude Code on Linux server for AI-driven development
2. **Code Editing**: PyCharm on macOS with Samba mount (no sync needed)
3. **Desktop Testing**: Flutter desktop on macOS for rapid UI testing
4. **Mobile Verification**: Occasional Android device testing

## Quick Start

### Prerequisites
- Flutter SDK (latest stable)
- Lupin FastAPI server running on port 7999
- ElevenLabs API key configured

### Running the Test UI
1. **Web Version**: Navigate to `http://localhost:7999/static/lupin-mobile-test/`
2. **Desktop Version**: `flutter run -d macos` (macOS) or `flutter run -d linux` (Linux)
3. **Mobile Version**: `flutter run` with connected device/emulator

### Running the FastAPI Server
```bash
# From parent Lupin project root
src/scripts/run-fastapi-lupin.sh
```

## Project Structure

```
src/lupin-mobile/
├── lib/                          # Flutter application code
│   ├── features/                 # Feature-specific UI and logic
│   │   ├── auth/                 # Authentication feature
│   │   ├── home/                 # Home screen with TTS testing
│   │   ├── notifications/        # Notification management
│   │   └── queue/                # Job queue management
│   ├── services/                 # Core services
│   │   ├── tts/                  # TTS provider abstraction
│   │   └── websocket/            # WebSocket communication
│   ├── shared/                   # Shared models and utilities
│   └── core/                     # App constants and themes
├── src/                          # Project documentation and scripts
│   ├── rnd/                      # Research and planning documents
│   └── scripts/                  # Build and utility scripts
├── android/                      # Android platform configuration
├── ios/                          # iOS platform configuration
├── web/                          # Web platform configuration
└── test/                         # Test files
```

## Research and Planning Documents

### Development Strategy
- **[Mobile App Development Options](src/rnd/2025.07.06-mobile-app-development-options.md.txt)** - Technology stack analysis and framework comparison
- **[Mobile Development Strategy](src/rnd/2025.07.07-mobile-development-strategy.md)** - Comprehensive development approach and methodology
- **[Development Workflow Plan](src/rnd/2025.07.07-development-workflow-plan.md)** - Hybrid development environment setup

### Technical Implementation
- **[TTS Implementation Plan](src/rnd/2025.07.07-tts-implementation-plan.md)** - Comprehensive TTS streaming architecture and implementation guide
- **[Architecture Deep Dive](src/rnd/2025.07.07-architecture-deep-dive.md)** - Detailed technical architecture and design decisions
- **[Flutter UI Specification](src/rnd/2025.07.07-flutter-ui-specification.md)** - UI/UX design and component specifications

### Research Analysis
- **[TTS Streaming Comparison (ChatGPT)](src/rnd/2025.07.07-tts-streaming-comparison-chatgpt.md)** - TTS provider research and analysis
- **[TTS Streaming Comparison (Claude)](src/rnd/2025.07.07-tts-streaming-comparison-claude.md)** - Additional TTS technology evaluation

### Project Planning
- **[Project Initialization Plan](src/rnd/2025.07.06-project-initialization-plan.md)** - Initial project setup and milestone planning

### Long-Running Jobs on Mobile (2026-09)
- **[Long-Running Quick Ask: Progress, Interrupts, and a Notification Pane](src/rnd/2026.09.04-long-running-quick-ask-notification-pane.md)** - What happens when a Quick Ask becomes a 2-20 minute job: the progress-as-answer defect (since fixed in `649f458`), what the browser client already does (job Activity Log + in-place progress rows + a queued Action Required pane), what mobile's focus mode can and cannot do, and three design options with a recommendation. **Plan only; the cap change it recommends is not implemented.**

### Spoken Questions: Two Legs or One (2026-09)
- **[Send the Text Back, or Post Audio Straight Into Ask?](src/rnd/2026.09.11-voice-one-leg-ask-decision-brief.md)** - Decision brief for row `9df9f1c2`, with both legs timed separately on Rick's own recording: transcript back 278 ms, text submission 455 ms (425 of it ask's own work), one-leg mp3 door 745 ms. On the server the saving is ~0 ms; the real saving is the gap between the draft reaching the phone and the second POST. The "return the transcript from the audio door" idea already exists on the mp3 door. Options A–D, recommendation C built as D. **Decided 2026-09-11** (review-first setting, streamed two-part reply, phone probe, 16 kHz after a check).
- **[Spoken Quick Ask, One Leg — Implementation Plan](src/rnd/2026.09.11-spoken-ask-streamed-door-implementation-plan.md)** - The build plan for those rulings: a new `POST /api/v2/ask-audio` streaming two NDJSON lines (transcript, then the full `AskResponse` with the job ID), transcription and ask off the event loop, unique temp files; on the phone a review-first/send-immediately toggle, a stream reader in `QueueRepository`, one branch in `QuickAskBloc` reusing `_applyResolvedAsk`, and cancel-before-job-ID. Test matrix per tier. **Plan only; awaiting Rick's okay.**
- **[Emulator UI Check List](src/rnd/2026.09.18-emulator-ui-check-list.md)** - Nine UI changes from 2026-09-16 and 2026-09-17 to confirm after one rebuild: the sign-in password and eye, the live-seat rail and refresh, sender colours, the 50/50 doc split, the full-width review box, the blank-capture message, and the `/api/v2/transcribe` log line.
- **[How To: Put the App on Your Phone and Record the Accuracy Clips](src/rnd/2026.09.16-phone-install-and-record-how-to.md)** - A 15-minute recipe for row `9b1f7701`: install a debug build on the handset over USB, switch to LAN DEV, record about 10 WAV questions with Keep voice recordings on, and copy them with `run-as` into `lupin/io/opus-accuracy/recordings/`. Explains why the phone records WAV and not Ogg: the accuracy test makes its own 32 kbps Opus copy, and only a real phone's microphone processing makes the comparison honest. The app's own Opus capture is a later format check the emulator can do.
- **[Phone Device Session Script](src/rnd/2026.09.15-phone-device-session-script.md)** - Rick's ~20-minute handset sitting for rows `c51e92da` and `9b1f7701`: install a fresh wip build, run the network round-trip probe on wifi then LTE and pull the JSONL logs, then record ~10 real questions for the Opus 32 kbps accuracy comparison. Flags two preconditions: the bundled server address only works in the emulator, and the app deletes its WAV recordings after upload today.

- **[JDK 25 Build Failure — Why Upgrading Gradle Does Not Fix It](src/rnd/2026.09.15-jdk-gradle-flutter-compatibility.md)** - The laptop's JDK 25.0.3 breaks the build with a bare `25.0.3` as its whole error. Upgrading Gradle is not available to us: Flutter 3.32's `gradle_utils.dart` caps Gradle at 8.12 and AGP at 8.7.3, exactly what this repo pins — so Gradle 9 requires a Flutter upgrade first, and even AGP 9.4.0 still lists JDK 17, never 25. Compatibility table with sources, the three paths costed, and how far behind our vendored Flutter 3.32.0 is (five stables, ~15 months) with nothing in those releases this app needs. Carries a dated correction: the bundled Android Studio JDK is **not** a constant — Studio 2024.2–2025.3 bundle JBR 21 but **Studio 2026.1 (Quail) bundles JBR 25.0.3**, so reusing Studio's JBR is not an option on a current Studio. Also establishes that the laptop builds with its own Flutter **3.35.1**, not the vendored 3.32.0, and that 3.35.1 lifts only the AGP cap (8.7.3 → 8.9.1) while leaving the Gradle cap at 8.12 — zero progress toward JDK 25. Plus two independent blockers: unaccepted Android licences, and a terminal running under Rosetta. **Recommendation: install a separate JDK 21 and point the build at it; no repo file changes.**

### Fleet Panes on Mobile (2026-09)
- **[Post-Game: The Fleet-Panes Cascade and Build](src/rnd/2026.09.20-postgame-fleet-panes-build.md)** - What one evening of a manager plus three seats actually produced, and the three measurements worth keeping. Chloé's mutation arm C **killed 4 tests while 22 stayed green** — three files looked like they covered the same dial, and each proved one half while handing in the other, so unit tests either side of a seam are *structurally* incapable of failing on the seam. One defect family wore three faces in one night, twice as a false alarm and once as false comfort (a worktree measuring the wrong specimen: a bare `flutter analyze` walking the symlinked SDK for 7,744 phantom errors, and two wire-contract tests silently skipping on a CWD-relative probe). And an analyzer exclusion is only honest with a **measured number** beside it — three of four proposed patterns matched zero files, and the same zero got opposite verdicts for reasons the file now states out loud. Also: the DM condenser mangled at least four messages, so put decisions in the first two lines. **Five phases built, reviewed and merged; union verified green; nothing pushed.**

- **[The Five Fleet Accordions — Check-In Briefing](src/rnd/2026.09.22-fleet-accordions-check-in-briefing.md)** - State of play for Rick's 09-22 check-in, measured rather than recalled: all five surfaces built, merged and reachable from `home_screen.dart` (wiring lines named), suite `1658 passed / 1 skipped / 0 failed` re-run on the current tree. The gap worth the conversation: **not one of the five has ever run on a device or emulator** — the 09-18 checklist has thirteen items and none touch them, so everything green here is green in `flutter_tester`, including the deliberate `inactive` exclusion in `broadcast_bloc.dart:243` whose failure mode is a false negative. Carries two corrections (the unpushed count is **15, not 11** — `origin` sits at `9d6e396` from 09-19, so the set reaches back past Phase 5 to the whole parity-guard arc; and a pane test answers "is it reachable?" *yes by construction*), the three fake-async traps that each cost a seat an evening, and three small proposals. **Briefing only; the plan is the conversation it is for. Push is not on the list.**

- **[Emulator Walk-Through: The Five Fleet Accordions](src/rnd/2026.09.22-emulator-walkthrough-five-accordions.md)** - The first time any of the five will be seen running: 14 items, each naming what it proves that no test can reach. Exists because the 09-18 checklist has thirteen items and **zero touch these five** — everything green about the accordions is green in `flutter_tester`. Items **10-13 carry the value**: no real broadcast has ever been fired from this app; the `inactive` exclusion at `broadcast_bloc.dart:243` is a judgement call **unmeasured on hardware** whose failure direction is a false negative (shade pull must NOT trip the guard, a real background MUST — both directions or neither number means anything); and the ack tally surviving navigation is the entire reason that bloc sits at app root. Carries an operational warning in bold: **a send hits every live seat**, which is why the Phase 5 fixtures were transcribed rather than fired. **A failure is a bug for Tiffany — paste the item number and what you saw.**

- **[Walk-Through Findings: The Work Plan](src/rnd/2026.09.22-walkthrough-findings-work-plan.md)** - Ten items Rick found on the emulator, costed and ordered, plus the three-part answer to "what does the offline indicator do" (a row filter, an unreachable *arbiter*, and an unreachable *server* — three different surfaces). **Two of the ten are not what they look like**: Fleet Status' perpetual spinner traces to a `pollOnce` path where a cancelled cap request returns **without adding Loaded or Failed**, leaving `composite` and `error` both null, which is precisely the builder's spinner branch — a poll that returns without changing state hangs the pane whatever triggered it; and the Holding Area's "grouping bug" is **working as designed**, because `groupByFiler` keys on the whole `created_by` including the session hash so that approve-all's blast radius can never exceed the name on the button — per-persona grouping is therefore a **ruling, not a tidy-up** (options A/B/C, recommendation C, and B refused without explicit words). Also: the Broadcast recipient picker is the biggest item and is **gated on whether the endpoint accepts a recipient list at all** — a question before a build, or the picker's selection gets discarded. **Plan only; nothing built. Sizes are estimates and the least trustworthy is the one whose shape a contract check may change.**
- **[Fleet Pane Parity: Crew Post-Game](src/rnd/2026.09.23-fleet-pane-parity-crew-post-game.md)** - Two workers closed every gap-analysis row in one evening (suite 1692 → 1904, measured on each merge). The finding: an optional named argument on a shared widget can vanish in a rebase with no compiler, git or bloc-test signal — caught once by reading a staged diff, then proven unguarded on the other pane.
- **[Fleet Panes Phase 2: Interactivity Gap Analysis](src/rnd/2026.09.23-fleet-panes-phase-2-gap-analysis.md)** - María's code census of the five panes against the plan, answering Rick's row `b422b23d`: Phase 1 did layouts, Phase 2 was meant to bring live editing. **Top gaps**: the Task List offers only approve and unpark (park, demote, drop, won't-fix and fixed are built but unreachable); priority and owner can't be edited on either task pane; the Holding Area never polls. One shared reason sheet closes both the Task List verbs and the Holding Area's per-row verbs. **Census only; nothing built. Goes to Rick for staffing.**

### In-App Document Viewer (2026-09)
- **[Abstract Doc-Link Viewer — Feasibility & Implementation Plan](src/rnd/2026.09.08-abstract-doc-link-viewer-feasibility.md)** - Can the app show an icon on abstracts that carry a doc link, and render the document in-app? Yes, and cheaper than expected: `/api/docs/file` returns **raw** markdown/text/code over the Dio that already injects the Bearer token, so no WebView and no second auth path. Covers the Flutter-vs-native-Android toolkit answer, the `flutter_markdown` discontinuation, the link shapes to parse, and a 4-phase plan. **Plan only; nothing implemented.**
- **[Abstract Rendering + Doc-Link Viewer — Implementation Plan](src/rnd/2026.09.08-abstract-doc-link-viewer-implementation-plan.md)** - The build plan behind the feasibility study: conditional markdown rendering of `abstract` inline in notification cards, an icon badge when the abstract carries a doc link, and a polymorphic in-app viewer for the target (markdown / source / image / directory). 4 phases, file-by-file, with the test matrix and acceptance criteria. **Plan only; awaiting go.**

### Notification Suppression (2026-09)
- **[Demo-Time Notification Toggle](src/rnd/2026.09.04-demo-time-notification-toggle.md)** - Four options for silencing duplicated announcements and interrupting manager asks on the emulator, plus the WebSocket-to-TTS path trace behind them. **Awaiting a decision; nothing implemented.**

### Focus-Mode Voice Chat + FCM Wake-Up (2026-06)
- **[Focus-Mode Voice Chat doc-set](src/rnd/2026.06.11-focus-mode-voice-chat/00-index.md)** - Multi-stage plan-of-record: focus-mode default surface (badge rail + serial TTS with pause/resume + Whisper-ASR voice replies) and the FCM silent-relay wake-up; cascade-shaped sections S1-S6, awaiting `/plan-review-cascaded`
- **[PIP Redline Draft: Workflow-Guidance Ledger](src/rnd/2026.06.12-pip-redline-draft-workflow-guidance-ledger.md)** - Draft (NOT landed) redlines folding the 14-entry cascade-focus-mode ledger into planning-is-prompting canonical docs; postgame ratification checklist
- **[Legacy Voice Stack Retirement Scoping](src/rnd/2026.06.12-legacy-voice-stack-retirement-scoping.md)** - Read-only audit of the flutter_sound/VoiceInputOutputService legacy stack: inventory, gap analysis, phased retirement plan (GO posture, unscheduled)
- **[Two-File Contract Pattern Explainer](src/rnd/2026.06.12-two-file-contract-pattern-explainer.md)** - How the S5/S6 cross-repo interface spec lives verbatim in both repos with same-round amendment propagation + element-wise comparison AC; written for postgame item 5
- **[cosa-voice Resume-Seat Primitive Ticket Draft](src/rnd/2026.06.12-cosa-voice-resume-seat-primitive-ticket-draft.md)** - Parent-side feature ticket per postgame decision 1: listener-level un-park of rate-limit-parked worker seats (detection, human-word-gated action, audit) + the !-prefix interim protocol
- **[Joint Post-Game: Focus-Mode Build Night](src/rnd/2026.06.12-joint-postgame-focus-mode-build.md)** - Manager 🦉 + Observer 🌸 joint record with Rick's live rulings per item (6 decided / 1 parked), the bilateral comms-meta lesson + 3 convention pins, and the 8-action consolidated ledger
- **[PoC Laptop-Build Runbook](src/rnd/2026.06.12-poc-laptop-build-runbook.md)** - Zero → focus-mode PoC on a real device: wraps the existing rsync/build-and-deploy scripts, FCM-OFF guidance, and the critical real-device LAN-IP repoint (bundled dev URL `10.0.2.2` is emulator-only); ends at the fm1–fm6 acceptance gate
- **[Legacy Quarantine Triage](src/rnd/2026.06.12-legacy-quarantine-triage.md)** - Per-file disposition of all 25 quarantined test files (rides-retirement / rides-follow-on / resurrect-candidate); the one real lost-coverage flag is `PerformanceMonitor`; closes the 2026-05-11 quarantine-triage TODO debt
- **[Focus-Mode Status Summary](src/rnd/2026.06.23-focus-mode-status-summary.md)** - One-page readable answer to "where are we on the focus UI?": all 6 sections AI-complete + committed (b34fa01, not pushed), suite 406✅; remaining work is all HUMAN/on-device (Firebase console, S5 Phase-0 probe, device gates); the no-Firebase PoC fast path
- **[Focus UI: Active / Recent-24h Session Filter](src/rnd/2026.06.25-focus-ui-active-history-filter.md)** - PLANNING doc for making the Focus rail default to currently-active sessions with a toggle to a rolling 24h history; mirrors the web notifications/multiplexer recency math (🟢 <1h / 🟡 <24h, Mr Radio-verified), adds `lastActivityBySender` + `FocusFilter` state + a 30s aging tick; M3 `SegmentedButton` toolbar; pure client-side, no backend work
- [2026.08.21 — v2 cutover wave 1: /api/push + retry → /api/v2/ask](src/rnd/2026.08.21-v2-cutover-wave1-ask.md)
- [2026.08.21 — Focus rail liveness + persona icons, notification stop-list, progress-group collapse (plan)](src/rnd/2026.08.21-focus-rail-liveness-icons-and-notification-stop-list.md)
- [2026.08.29 — Quick Ask: push-to-talk Q&A screen (plan + implementation record)](src/rnd/2026.08.29-quick-ask-push-to-talk-screen.md) — hold-to-record → `/api/v2/ask` → todo/running/done via the `job_state_transition` frames mobile previously dropped, plus the first cut of the generic "server asks the phone a question" surface (four doors, status-first branching). **Cascaded review complete; implemented 2026-08-29 across 62 commits.** Open at close: AC-S2.8 (cited twice, never defined) and the AC-G3 cached-question clause (deferred to a scheduled `:8000` probe)
- [2026.08.29 — Cascade Quick Ask recon checklist](src/rnd/2026.08.29-cascade-quick-ask-recon-checklist.md) — the reviewer-side recon sheet driving the cascaded review of the Quick Ask plan

### v0.1.7 — Bug Fixes & Lifecycle Wiring (2026-04)
- **[Hot Bugs: URL-Encoding + Post-Login Investigation](src/rnd/v0.1.7/2026.04.19-hot-bugs-url-encoding-and-post-login-investigation.md)** - `NotificationRepository` path-param URL-encoding fix and post-login behavior audit findings
- **[WS Lifecycle Auth Wiring Plan](src/rnd/v0.1.7/2026.04.19-ws-lifecycle-auth-wiring-plan.md)** - Design for driving `WebSocketService.connect/disconnect` from `AuthBloc` state transitions via a `WsLifecycleListener` widget
- [2026.08.21 — v2 cutover wave 2 readiness](src/rnd/2026.08.21-v2-cutover-wave-2-readiness.md) — eleven submit doors vs `/api/v2/submit` contract: what maps, what does not, and what the mobile repo landed now

## Project Documentation

- **[Session History](history.md)** - Detailed development session summaries and progress tracking
- **[Development Configuration](CLAUDE.md)** - Claude Code configuration and development guidelines
- **[Private Configuration](CLAUDE.local.md)** - Local development settings and preferences

## v0.1.6 Resync Implementation Status

### ✅ Tier 1 — Auth (Complete 2026-04-15)
- JWT login/logout with token refresh
- Biometric unlock (local_auth)
- WS session persistence across app lifecycle
- Dev/Test context toggle

### ✅ Tier 2 — Notifications + Decision Proxy (Complete 2026-04-16)
- Inbox with flat conversation list
- Interactive yes/no and multi-choice prompt sheet
- Trust dashboard with domain/mode overview
- NotificationBloc + DecisionProxyBloc

### ✅ Tier 3 — Queue / CJ Flow + Claude Code (Complete 2026-04-16)
- Queue dashboard with live status badges
- Job detail screen with WS-driven progress
- Submit job sheet (12 agent types)
- Claude Code chat + session list
- WS bridge: queue/CC events → BLoCs

### ✅ Tier 4 — Agentic Jobs (Complete 2026-04-16)
- AgenticHubScreen + 9 job-type forms
- Single AgenticRepository (10 endpoints)
- AgenticSubmissionBloc → navigates to JobDetailScreen on success
- IoFileService: binary download, cache, share, open-in-app
- Artifact viewers: markdown / audio / slide deck
- BugFixExpediter entry from dead job's JobDetailScreen

### 📋 Pending Polish
- On-device smoke tests
- In-app audioplayers (currently download-and-share)
- TimeSavedDashboard + StatsRepository (fl_chart — deferred)
- NotificationsExternalUpdate WS wiring
- Date-grouped ConversationScreen

## API Integration

### FastAPI Endpoints
- **WebSocket**: `/ws/{session_id}` - Real-time communication
- **TTS (OpenAI)**: `POST /api/get-speech` - OpenAI TTS streaming
- **TTS (ElevenLabs)**: `POST /api/get-speech-elevenlabs` - ElevenLabs TTS streaming
- **Session Management**: `GET /api/get-session-id` - WebSocket session initialization

### WebSocket Authentication Flow
1. Retrieve session ID from FastAPI
2. Establish WebSocket connection with session ID
3. Send authentication token for validation
4. Begin TTS streaming communication

## Performance Metrics

### Current Performance (Phase 1)
- **ElevenLabs Latency**: ~150-250ms total (meets target)
- **OpenAI Latency**: ~1-3 seconds (baseline comparison)
- **WebSocket Connection**: <100ms establishment
- **Chunk Processing**: Real-time streaming with 8KB chunks
- **Provider Switching**: Instantaneous UI toggle

## Contributing

This project is part of the larger Lupin AI ecosystem. Development follows the hybrid workflow with Claude Code for AI-driven development and traditional IDE tools for editing and testing.

### Development Environment
- **Primary Development**: Linux server with Claude Code
- **Code Editing**: PyCharm with Samba mount for advanced IDE features
- **Testing**: Flutter desktop for rapid iteration, mobile devices for verification

## License

Part of the Lupin AI assistant project ecosystem.

---

*Last Updated: 2026-04-16 — Lupin v0.1.6 Resync All 4 Tiers Complete (140/140 tests)*