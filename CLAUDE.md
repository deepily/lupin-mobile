# LUPIN MOBILE DEVELOPMENT GUIDE

## PROJECT OVERVIEW
This is a standalone mobile application repository embedded as a subtree within the larger Lupin project ecosystem. The goal is to develop a quick Android app prototype with voice input/output, WebSocket updates, and HTTP calls to interface with the Lupin backend.

## PROJECT IDENTIFIERS
- **SHORT_PROJECT_PREFIX**: [LUPIN-MOBILE]
- **Repository Type**: Standalone mobile app (subtree within parent Lupin repo)
- **Primary Platform**: Android (with potential for cross-platform expansion)

## REPOSITORY STRUCTURE
```
src/lupin-mobile/
├── src/
│   ├── rnd/                    # Research and planning documents
│   │   └── 2025.07.06-mobile-app-development-options.md.txt
│   └── scripts/                # Build and utility scripts
├── CLAUDE.md                   # This configuration file
├── CLAUDE.local.md             # Private project configuration
├── README.md                   # Project documentation
└── LICENSE                     # License file
```

## DEVELOPMENT TECHNOLOGY STACK
Based on the mobile development options analysis, the following technologies are recommended:

### Primary Options (in order of preference):
1. **Flutter (Dart)** - For rapid prototyping with hot reload
2. **React Native (JavaScript/TypeScript)** - For web developer familiarity
3. **Hybrid Web App (Cordova/Capacitor)** - For maximum code reuse
4. **Native Android (Kotlin)** - For maximum control and performance

### Key Requirements:
- **Voice Input/Output**: Audio recording and playback capabilities
- **Real-time Communication**: WebSocket connections to Lupin backend
- **HTTP Requests**: RESTful API calls
- **Offline Caching**: Local storage for audio snippets
- **Device Integration**: Vibration, Bluetooth audio support
- **Rapid Development**: Hot reload for fast iteration

### TTS Technology Selection (Based on 2025.07.07 Research):
- **Provider**: ElevenLabs (Flash v2.5 model)
- **Latency**: ~75ms inference, 150-250ms total (meets 250-500ms target)
- **Protocol**: WebSocket streaming with bidirectional support
- **Audio Format**: PCM 44.1kHz (primary), MP3 fallback for compatibility
- **Cost**: $5.00 per million characters
- **Key Features**:
  - Real-time streaming via WebSocket
  - Low-latency Flash models optimized for conversational AI
  - Cross-platform audio format support
  - Connection pooling for scalability

## BACKEND INTEGRATION
- **Primary Backend**: Lupin FastAPI server (runs on port 7999)
- **WebSocket Endpoint**: Real-time communication with Lupin agents
- **HTTP API**: RESTful endpoints for data exchange
- **Audio Processing**: Server-side heavy lifting, client handles I/O
- **TTS Proxy Architecture**:
  - FastAPI WebSocket proxy to ElevenLabs streaming API
  - Bidirectional audio streaming with minimal latency
  - Connection pooling for concurrent TTS requests
  - Audio chunk caching for frequently used phrases

## DEVELOPMENT COMMANDS
```bash
# Always use the wrapper; bare `flutter` is not on every seat's PATH.

# Testing
./flutter.sh test                      # full suite, the merge gate (green on the exact sha)
./flutter.sh test --coverage           # lcov at coverage/lcov.info
./flutter.sh analyze <changed files>   # repo-wide analyze has pre-existing noise

# Android debug APK on the dev server (toolchain installed 2026-09-27, row 651e3956)
#   JDK 21 at ~/opt/jdk-21, SDK at ~/Android/Sdk; `flutter config` already points at both.
#   Build in the MAIN checkout: worktrees lack android/app/google-services.json (gitignored).
#   Worker seats are capped at 8 GiB, but android/gradle.properties asks Gradle for
#   -Xmx8G plus 4G metaspace, so an unmodified build is OOM-killed and reports only
#   "Gradle build daemon disappeared unexpectedly". Pass the override below (session-local).
JAVA_HOME=$HOME/opt/jdk-21 \
GRADLE_OPTS="-Dorg.gradle.jvmargs=-Xmx4g\ -XX:MaxMetaspaceSize=1g\ -XX:ReservedCodeCacheSize=256m -Dkotlin.daemon.jvmargs=-Xmx1500m -Dorg.gradle.workers.max=6" \
./flutter.sh build apk --debug         # ~7 min cold, ~64 s warm; installing to the phone still needs the laptop or adb

# The same build, wrapped (main checkout only, one at a time, memory override built in):
src/scripts/build-apk-on-server.sh --fcm   # --fcm keeps push wake-ups in; without it they are compiled OUT
# From the laptop: build on the server over ssh, then install to the phone (row f681440d)
src/scripts/deploy-apk-to-device.sh --build --fcm

# Manager's merge gate (analyzer vs base, docs gate, ignores, coverage, tool tests, full suite, AC-G2).
#   Run in the real checkout whose HEAD ends the range, with a clean tree and no untracked files.
#   Verdicts: PASS, PASS-WITH-WARNING (exit 0; read the warning line), FAIL, QUICK (--skip-suite), CANNOT RUN.
python3 tool/merge_gate.py --base <sha or branch> [--skip-suite] [--comments-only]
```

**Always rebuild the APK after a client change (Rick, 2026-09-28).** Whenever a client change or bug fix merges into the main checkout and the suite is green, run `src/scripts/build-apk-on-server.sh --fcm` there and say the APK is ready. Rick then only runs `deploy-apk-to-device.sh` (no flags) from the laptop. **Always pass `--fcm`**: a build without it silently has no background wake-ups, and nothing on the phone says so (Pocholo's review F3, 2026-09-28).

## CODE STYLE AND CONVENTIONS
- **File Naming**: Use dashes for non-code files (e.g., `mobile-app-config.md`)
- **Documentation**: Date prefixes use YYYY.MM.DD format
- **Research Documents**: Store in `src/rnd/` directory with date prefixes
- **Configuration**: Follow parent Lupin project conventions where applicable
- **Doc comments**: Follow `src/docs/docstring-standard.md`; rulings go in `src/docs/decisions/README.md`

## RAPID PROTOTYPING PRIORITIES
1. **Voice Interface**: Primary user interaction method
2. **Real-time Updates**: WebSocket communication with backend
3. **Offline Capability**: Cache audio snippets for offline playback
4. **Device Integration**: Vibration feedback, Bluetooth audio support
5. **Performance**: Smooth UI interactions and audio playback

## FRAMEWORK SELECTION CRITERIA
- **Development Speed**: Hot reload and fast iteration
- **Audio Support**: Proven voice recording/playback libraries
- **Network Capabilities**: WebSocket and HTTP support
- **Offline Storage**: Local caching mechanisms
- **Device APIs**: Access to vibration, Bluetooth, etc.
- **Community Support**: Active ecosystem and documentation

## TESTING AND DEPLOYMENT
- **Target Platform**: Android (minimum SDK TBD)
- **Testing**: Device/emulator testing during development
- **Distribution**: Development builds initially, Play Store consideration later
- **Performance**: Voice UI responsiveness and audio quality focus

## RESEARCH AND PLANNING
- All research documents stored in `src/rnd/` directory
- Planning documents use date prefixes (YYYY.MM.DD)
- Technology evaluation and framework selection documented
- Architecture decisions recorded for future reference

## INTEGRATION NOTES
- **Parent Repository**: This is a subtree within the larger Lupin ecosystem
- **Git Management**: Local changes only, no git operations on parent repo
- **Dependency Management**: Independent of parent project dependencies
- **Configuration**: Standalone configuration files for mobile-specific settings

## NOTIFICATION SYSTEM
- **Script Location**: `src/scripts/notify.sh`
- **Target Email**: ricardo.felipe.ruiz@gmail.com
- **API Key**: claude_code_simple_key
- **Usage**: Progress updates, approvals, and blocked states

## DEVELOPMENT WORKFLOW
1. **Framework Selection**: Choose optimal technology stack
2. **Basic Setup**: Initialize project with chosen framework
3. **Core Features**: Implement voice, WebSocket, HTTP capabilities
4. **Device Integration**: Add vibration, Bluetooth, offline storage
5. **Testing and Refinement**: Iterate based on testing feedback
6. **Documentation**: Update planning and progress documents

## REPOSITORY MANAGEMENT
- **Important**: This is a standalone repository that cannot be git-managed when working within the parent Lupin project
- **Changes**: Can be made to files but git operations should be handled separately
- **Dependencies**: Independent package management from parent project

---

## PLANNING-IS-PROMPTING WORKFLOWS

Installed via `installation-wizard.md` on 2026-04-15 (full set, all 13 workflow groups).

**Configuration**:
- Short Prefix: `[LUPIN-MOBILE]`
- Project Name: Lupin Mobile
- History file: `./history.md`
- Archive directory: `./history/`
- Backup source: `/mnt/DATA01/include/www.deepily.ai/projects/lupin/src/lupin-mobile/`
- Backup destination: `/mnt/DATA02/include/www.deepily.ai/projects/lupin/src/lupin-mobile/`

**Slash Commands Available** (under `.claude/commands/`):

| Group | Commands |
|-------|----------|
| Session Management | `/plan-session-start`, `/plan-session-end`, `/plan-session-checkpoint` |
| History Management | `/plan-history-management` |
| TODO Management | `/plan-todo` |
| Bug Fix Mode | `/plan-bug-fix-mode[-start/-continue/-close/-wrap]` |
| Planning is Prompting Core | `/p-is-p-00-start-here`, `/p-is-p-01-planning`, `/p-is-p-02-documentation` |
| Backup Infrastructure | `/plan-backup-check`, `/plan-backup`, `/plan-backup-write` |
| Testing Workflows | `/plan-test-baseline`, `/plan-test-remediation`, `/plan-test-harness-update` |
| Skills Management | `/plan-skills-management[-discover/-create/-edit/-audit/-delete]` |
| Branch / PR / Merge | `/plan-branch-pr-and-merge` |
| Workflow Audit | `/plan-workflow-audit` |
| About | `/plan-about` |
| Session Close | `/plan-last-call` (🔔 — two-stage close; deliverables `push` → `/plan-session-end` push step · `backup` → `/plan-backup-write` · `post-game` → `/plan-post-game`), `/plan-post-game` |
| Install / Uninstall Wizards | `/plan-install-wizard`, `/plan-uninstall-wizard` |

**Behavioral Directives** (already established globally in `~/.claude/CLAUDE.md`):
- Plan Serialization (serialize plans to `src/rnd/`)
- Mermaid Diagrams

**Canonical Workflows**: `$PLANNING_IS_PROMPTING_ROOT/workflow/*.md` — slash commands above are thin wrappers that load these.

## SESSION WORKFLOWS

**Session Start**: Use `/plan-session-start` or see planning-is-prompting → workflow/session-start.md
**Session End**: Use `/plan-session-end` or see planning-is-prompting → workflow/session-end.md

## Doc Viewer Scope

When sending document viewer links from this repo, use:

- **Scope name**: `lupin-mobile`
- **Allowed prefixes** (per Lupin INI): wildcard (any path under repo root)
- **Source of truth**: Lupin's `lupin-app.ini` § `external repos`
- **Runtime discovery**: inspect the `doc_scope` field returned by `mcp__cosa-voice__get_session_info()`

Example: `/app/docs?path=lupin-mobile/README.md`

The project name is the **first segment of `path`**. The old `&scope=` parameter was retired on 2026-05-21: a link like `path=src/rnd/x.md&scope=lupin-mobile` reads `src` as the project and 404s (this happened on 2026-09-16).