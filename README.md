# Lupin Mobile

A sophisticated Android mobile client for the Lupin AI assistant system, featuring voice interaction, real-time communication, and offline capabilities.

## 🚀 Project Status

**Lupin v0.1.6 Resync — All 4 Tiers Complete** ✅ — On-device validation pending

### What's New (v0.1.6 Resync)
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

### Long-Running Jobs on Mobile
- **[Long-Running Quick Ask: Progress, Interrupts, and a Notification Pane](src/rnd/2026.09.04-long-running-quick-ask-notification-pane.md)** - Three design options for a Quick Ask that runs for minutes. Plan only.

### Spoken Questions: Two Legs or One
- **[Send the Text Back, or Post Audio Straight Into Ask?](src/rnd/2026.09.11-voice-one-leg-ask-decision-brief.md)** - Decision brief with both legs timed on a real recording. Decided.
- **[Spoken Quick Ask, One Leg — Implementation Plan](src/rnd/2026.09.11-spoken-ask-streamed-door-implementation-plan.md)** - The build plan for those rulings: a streamed `POST /api/v2/ask-audio` door and the phone side.
- **[Emulator UI Check List](src/rnd/2026.09.18-emulator-ui-check-list.md)** - Thirteen UI items to confirm on the emulator after one rebuild.
- **[How To: Put the App on Your Phone and Record the Accuracy Clips](src/rnd/2026.09.16-phone-install-and-record-how-to.md)** - A recipe for the accuracy test recordings.
- **[Phone Device Session Script](src/rnd/2026.09.15-phone-device-session-script.md)** - A handset sitting of about twenty minutes: fresh build, network probe, then the recordings.

- **[JDK 25 Build Failure — Why Upgrading Gradle Does Not Fix It](src/rnd/2026.09.15-jdk-gradle-flutter-compatibility.md)** - Why JDK 25 breaks the build, with a compatibility table. Recommendation: install a separate JDK 21.

### Fleet Panes on Mobile
- **[Post-Game: The Fleet-Panes Cascade and Build](src/rnd/2026.09.20-postgame-fleet-panes-build.md)** - What one evening of a manager and three seats produced, and three measurements worth keeping.

- **[The Five Fleet Accordions — Check-In Briefing](src/rnd/2026.09.22-fleet-accordions-check-in-briefing.md)** - State of the five fleet surfaces at a check-in with Rick. Briefing only.

- **[Emulator Walk-Through: The Five Fleet Accordions](src/rnd/2026.09.22-emulator-walkthrough-five-accordions.md)** - Fourteen items to check on the emulator, each naming what no test can reach.

- **[Walk-Through Findings: The Work Plan](src/rnd/2026.09.22-walkthrough-findings-work-plan.md)** - Ten items Rick found on the emulator, costed and ordered. Plan only.
- **[Fleet Pane Parity: Crew Post-Game](src/rnd/2026.09.23-fleet-pane-parity-crew-post-game.md)** - Two workers closed every gap-analysis row in one evening, and what a rebase silently dropped.
- **[Mobile Docs Track: Crew Post-Game](src/docs/post-games/v0.2.2/2026.10.03-mobile-docs-track-crew-post-game.md)** - Three days, five seats: public members in `lib/` got doc comments with no behaviour change. Five rulings.
- **[Fleet Panes: Interactivity Gap Analysis](src/rnd/2026.09.23-fleet-panes-phase-2-gap-analysis.md)** - A code census of the five panes against the plan, with the top gaps. Census only.

### In-App Document Viewer
- **[Abstract Doc-Link Viewer — Feasibility & Implementation Plan](src/rnd/2026.09.08-abstract-doc-link-viewer-feasibility.md)** - Whether the app can render a linked document in-app. It can, with no WebView.
- **[Abstract Rendering + Doc-Link Viewer — Implementation Plan](src/rnd/2026.09.08-abstract-doc-link-viewer-implementation-plan.md)** - The build plan behind the feasibility study, in four phases with a test matrix.

### Notification Suppression
- **[Demo-Time Notification Toggle](src/rnd/2026.09.04-demo-time-notification-toggle.md)** - Four options for silencing duplicated announcements on the emulator.

### Focus-Mode Voice Chat + FCM Wake-Up
- **[Focus-Mode Voice Chat doc-set](src/rnd/2026.06.11-focus-mode-voice-chat/00-index.md)** - The multi-stage plan for the focus-mode surface and the FCM wake-up.
- **[Redline Draft: Workflow-Guidance Ledger](src/rnd/2026.06.12-pip-redline-draft-workflow-guidance-ledger.md)** - Draft redlines that fold a 14-entry ledger into the planning-is-prompting docs. Not landed.
- **[Legacy Voice Stack Retirement Scoping](src/rnd/2026.06.12-legacy-voice-stack-retirement-scoping.md)** - Read-only audit of the legacy voice stack, with a phased retirement plan.
- **[Two-File Contract Pattern Explainer](src/rnd/2026.06.12-two-file-contract-pattern-explainer.md)** - How one cross-repo interface spec lives word for word in both repos.
- **[cosa-voice Resume-Seat Primitive Ticket Draft](src/rnd/2026.06.12-cosa-voice-resume-seat-primitive-ticket-draft.md)** - Feature ticket draft: un-park worker seats that a rate limit parked.
- **[Joint Post-Game: Focus-Mode Build Night](src/rnd/2026.06.12-joint-postgame-focus-mode-build.md)** - Joint record by the manager and the observer, with Rick's rulings per item.
- **[PoC Laptop-Build Runbook](src/rnd/2026.06.12-poc-laptop-build-runbook.md)** - From nothing to the focus-mode proof of concept on a real device.
- **[Legacy Quarantine Triage](src/rnd/2026.06.12-legacy-quarantine-triage.md)** - What to do with each of the 25 quarantined test files.
- **[Focus-Mode Status Summary](src/rnd/2026.06.23-focus-mode-status-summary.md)** - A one-page answer to where the focus UI stood, and what was left for a person to do.
- **[Focus UI: Active / Recent-24h Session Filter](src/rnd/2026.06.25-focus-ui-active-history-filter.md)** - Planning doc: active sessions by default, with a toggle to a rolling 24 hours.
- [v2 cutover wave 1: /api/push + retry → /api/v2/ask](src/rnd/2026.08.21-v2-cutover-wave1-ask.md)
- [Focus rail liveness + persona icons, notification stop-list, progress-group collapse (plan)](src/rnd/2026.08.21-focus-rail-liveness-icons-and-notification-stop-list.md)
- [Quick Ask: push-to-talk Q&A screen (plan + implementation record)](src/rnd/2026.08.29-quick-ask-push-to-talk-screen.md) — hold to record, then `/api/v2/ask`, then live job states. Reviewed and built.
- [Cascade Quick Ask recon checklist](src/rnd/2026.08.29-cascade-quick-ask-recon-checklist.md) — the reviewer's recon sheet for the review of the Quick Ask plan

### Documentation Standard
- [Markdown cleanup and blocking plan](src/rnd/2026.10.13-plan-1-mobile-markdown-cleanup-and-blocking-plan.md) — a proposal to clean the live markdown pages, then refuse a bad markdown line at commit.

### v0.1.7 — Bug Fixes & Lifecycle Wiring
- **[Hot Bugs: URL-Encoding + Post-Login Investigation](src/rnd/v0.1.7/2026.04.19-hot-bugs-url-encoding-and-post-login-investigation.md)** - `NotificationRepository` path-param URL-encoding fix and post-login behavior audit findings
- **[WS Lifecycle Auth Wiring Plan](src/rnd/v0.1.7/2026.04.19-ws-lifecycle-auth-wiring-plan.md)** - Design for driving `WebSocketService.connect/disconnect` from `AuthBloc` state transitions via a `WsLifecycleListener` widget
- [v2 cutover wave 2 readiness](src/rnd/2026.08.21-v2-cutover-wave-2-readiness.md) — eleven submit doors against the `/api/v2/submit` contract: what maps and what does not

## Project Documentation

- **[Session History](history.md)** - Detailed development session summaries and progress tracking
- **[Development Configuration](CLAUDE.md)** - Claude Code configuration and development guidelines
- **Private Configuration** (`CLAUDE.local.md`) - Local development settings and preferences

## v0.1.6 Resync Implementation Status

### ✅ Tier 1 — Auth (Complete)
- JWT login/logout with token refresh
- Biometric unlock (local_auth)
- WS session persistence across app lifecycle
- Dev/Test context toggle

### ✅ Tier 2 — Notifications + Decision Proxy (Complete)
- Inbox with flat conversation list
- Interactive yes/no and multi-choice prompt sheet
- Trust dashboard with domain/mode overview
- NotificationBloc + DecisionProxyBloc

### ✅ Tier 3 — Queue / CJ Flow + Claude Code (Complete)
- Queue dashboard with live status badges
- Job detail screen with WS-driven progress
- Submit job sheet (12 agent types)
- Claude Code chat + session list
- WS bridge: queue/CC events → BLoCs

### ✅ Tier 4 — Agentic Jobs (Complete)
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

### Current Performance (first TTS build)
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

*Lupin v0.1.6 Resync: all 4 tiers complete (140/140 tests). Later work is in `history.md`.*