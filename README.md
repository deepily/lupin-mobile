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

### v0.1.7 — Bug Fixes & Lifecycle Wiring (2026-04)
- **[Hot Bugs: URL-Encoding + Post-Login Investigation](src/rnd/v0.1.7/2026.04.19-hot-bugs-url-encoding-and-post-login-investigation.md)** - `NotificationRepository` path-param URL-encoding fix and post-login behavior audit findings
- **[WS Lifecycle Auth Wiring Plan](src/rnd/v0.1.7/2026.04.19-ws-lifecycle-auth-wiring-plan.md)** - Design for driving `WebSocketService.connect/disconnect` from `AuthBloc` state transitions via a `WsLifecycleListener` widget

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