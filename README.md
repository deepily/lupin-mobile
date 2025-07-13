# Lupin Mobile

A sophisticated Android mobile client for the Lupin AI assistant system, featuring voice interaction, real-time communication, and offline capabilities.

## 🚀 Project Status

**95% Implementation Complete** ✅ - Ready for weekend final testing and deployment

### Recent Achievements (2025.07.10)
- ✅ **Android-First Conversion**: Native mobile dependencies enabled
- ✅ **Code Quality**: Improved from 8,794 to 1,392 analysis issues (84% improvement)
- ✅ **CI/CD Pipeline**: Complete GitHub Actions workflow for testing and releases
- ✅ **Documentation**: Design by Contract documentation added throughout codebase
- ✅ **TTS Integration**: Native AudioPlayer for low-latency audio streaming

### Current Capabilities
- **TTS Streaming**: Both OpenAI and ElevenLabs providers with WebSocket streaming
- **Provider Switching**: Easy toggling between TTS services via test UI
- **WebSocket Integration**: Session-based authentication and real-time communication
- **Test Interface**: Comprehensive Flutter web UI hosted on FastAPI (port 7999)
- **Cross-Platform**: Android, iOS, and web support

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

## Project Documentation

- **[Session History](history.md)** - Detailed development session summaries and progress tracking
- **[Development Configuration](CLAUDE.md)** - Claude Code configuration and development guidelines
- **[Private Configuration](CLAUDE.local.md)** - Local development settings and preferences

## Phase Implementation Status

### ✅ Phase 1: TTS Streaming Foundation (Completed 2025.07.07)
- ElevenLabs WebSocket streaming integration
- FastAPI parallel endpoint strategy
- Flutter test UI with provider switching
- Session-based WebSocket authentication
- Cross-platform project structure

### 🔄 Phase 2: Audio Optimization (In Progress)
- Platform-specific audio players (Android/iOS)
- Audio buffer management and optimization
- Caching system for frequently used phrases
- Enhanced UI/UX for voice assistant interface
- Performance monitoring and latency optimization

### 📋 Phase 3: Production Features (Planned)
- Connection retry logic and error recovery
- Offline mode with cached audio
- Voice selection and customization UI
- Comprehensive latency monitoring
- User preference management

### 📋 Phase 4: Advanced Features (Future)
- Multi-language support
- Voice cloning integration
- Advanced caching strategies
- Analytics and usage tracking
- App store deployment

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

*Last Updated: 2025.07.07 - Phase 1 TTS Implementation Complete*