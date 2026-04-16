import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../main.dart';
import '../../services/tts/tts_service.dart';
import '../../services/websocket/websocket_service.dart';
import '../auth/domain/auth_bloc.dart';
import '../auth/domain/auth_event.dart';
import '../auth/domain/auth_state.dart';
import '../decision_proxy/presentation/trust_dashboard_screen.dart';
import '../notifications/presentation/inbox_screen.dart';

class LupinHomeScreen extends StatefulWidget {
  const LupinHomeScreen({super.key});

  @override
  State<LupinHomeScreen> createState() => _LupinHomeScreenState();
}

class _LupinHomeScreenState extends State<LupinHomeScreen> {
  late final TTSService _ttsService;
  late final WebSocketService _webSocketService;
  
  String _connectionStatus = 'Disconnected';
  String _ttsStatus = 'Ready';
  
  @override
  void initState() {
    super.initState();
    _ttsService = getIt<TTSService>();
    _webSocketService = getIt<WebSocketService>();
    
    // Listen to connection and TTS status
    _setupListeners();
  }
  
  void _setupListeners() {
    // Listen to TTS status updates
    _ttsService.statusStream.listen((status) {
      if (mounted) {
        setState(() {
          _ttsStatus = status;
        });
      }
    });
  }
  
  Future<void> _connectWebSocket() async {
    try {
      setState(() {
        _connectionStatus = 'Connecting...';
      });
      
      await _webSocketService.connect(userId: 'lupin_mobile_user');
      
      setState(() {
        _connectionStatus = _webSocketService.isConnected ? 'Connected' : 'Failed';
      });
    } catch (e) {
      setState(() {
        _connectionStatus = 'Error: $e';
      });
    }
  }
  
  Future<void> _testElevenLabsTTS() async {
    try {
      await _ttsService.speak(
        'Hello from Lupin Mobile! This is a test of ElevenLabs TTS streaming.',
        provider: TTSProvider.elevenlabs,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('TTS Error: $e')),
      );
    }
  }
  
  Future<void> _testOpenAITTS() async {
    try {
      await _ttsService.speak(
        'Hello from Lupin Mobile! This is a test of OpenAI TTS.',
        provider: TTSProvider.openai,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('TTS Error: $e')),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lupin Mobile'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            tooltip: 'Inbox',
            icon: const Icon(Icons.inbox_outlined),
            onPressed: () {
              final s = context.read<AuthBloc>().state;
              if (s is AuthAuthenticated) {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => InboxScreen(userEmail: s.email),
                ));
              }
            },
          ),
          IconButton(
            tooltip: 'Trust',
            icon: const Icon(Icons.shield_outlined),
            onPressed: () {
              final s = context.read<AuthBloc>().state;
              if (s is AuthAuthenticated) {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => TrustDashboardScreen(userEmail: s.email),
                ));
              }
            },
          ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthBloc>().add(const AuthLogoutRequested()),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Voice Assistant',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            
            // Connection Status
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'WebSocket Connection',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Status: $_connectionStatus'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _connectWebSocket,
                      child: const Text('Connect'),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // TTS Status
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Text-to-Speech',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Status: $_ttsStatus'),
                    const SizedBox(height: 16),
                    
                    // ElevenLabs Test
                    ElevatedButton(
                      onPressed: _webSocketService.isConnected ? _testElevenLabsTTS : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Test ElevenLabs TTS'),
                    ),
                    
                    const SizedBox(height: 8),
                    
                    // OpenAI Test
                    ElevatedButton(
                      onPressed: _webSocketService.isConnected ? _testOpenAITTS : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Test OpenAI TTS'),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Current Provider
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Current TTS Provider',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Provider: ${_ttsService.getCurrentProvider().name}'),
                    const SizedBox(height: 16),
                    
                    // Provider Selection
                    DropdownButton<TTSProvider>(
                      value: _ttsService.getCurrentProvider(),
                      items: TTSProvider.values.map((provider) {
                        return DropdownMenuItem(
                          value: provider,
                          child: Text(provider.name.toUpperCase()),
                        );
                      }).toList(),
                      onChanged: (provider) {
                        if (provider != null) {
                          _ttsService.setProvider(provider);
                          setState(() {});
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            
            const Spacer(),
            
            const Text(
              'Phase 1: ElevenLabs Integration Complete',
              style: TextStyle(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}