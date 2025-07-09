import 'package:flutter/material.dart';
import 'core/app_initialization.dart';
import 'core/logging/logger.dart';
import 'core/error_handling/error_handler.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // Initialize core systems (logging, error handling, storage, DI)
    await AppInitialization.initialize(
      enableDebugLogging: true,
      enableFileLogging: true,
      enableRemoteLogging: false,
    );
    
    Logger.info('Lupin Mobile app starting...');
    
    // Run the app
    runApp(const LupinMobileApp());
    
  } catch (error, stackTrace) {
    // Critical initialization error - log and show error screen
    Logger.critical(
      'Failed to initialize application',
      error: error,
      stackTrace: stackTrace,
    );
    
    // Show minimal error app
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text(
                'App Initialization Failed',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Please restart the app',
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    ));
  }
}