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

## BACKEND INTEGRATION
- **Primary Backend**: Lupin FastAPI server (runs on port 7999)
- **WebSocket Endpoint**: Real-time communication with Lupin agents
- **HTTP API**: RESTful endpoints for data exchange
- **Audio Processing**: Server-side heavy lifting, client handles I/O

## DEVELOPMENT COMMANDS
```bash
# Development server commands (if applicable)
# TBD based on chosen framework

# Build commands
# TBD based on chosen framework

# Testing commands
# TBD based on chosen framework
```

## CODE STYLE AND CONVENTIONS
- **File Naming**: Use dashes for non-code files (e.g., `mobile-app-config.md`)
- **Documentation**: Date prefixes use YYYY.MM.DD format
- **Research Documents**: Store in `src/rnd/` directory with date prefixes
- **Configuration**: Follow parent Lupin project conventions where applicable

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