import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/constants/app_constants.dart';
import 'package:lupin_mobile/services/auth/server_context_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _configJson = '''
{
  "default": "dev",
  "contexts": {
    "dev":  { "label": "DEV",  "baseUrl": "http://dev.example:7999",  "wsUrl": "ws://dev.example:7999"  },
    "test": { "label": "TEST", "baseUrl": "http://test.example:8000", "wsUrl": "ws://test.example:8000" }
  }
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Inject the bundled asset for server-contexts.json.
    ServicesBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler("flutter/assets", (message) async {
        final key = const StringCodec().decodeMessage(message);
        if (key == "assets/config/server-contexts.json") {
          return const StringCodec().encodeMessage(_configJson);
        }
        return null;
      });
  });

  group("ServerContextService", () {
    test("load picks default context on first launch", () async {
      final prefs = await SharedPreferences.getInstance();
      final svc   = await ServerContextService.load(prefs);

      expect(svc.active, ServerContext.dev);
      expect(svc.baseUrl, "http://dev.example:7999");
      expect(svc.wsUrl,   "ws://dev.example:7999");
      expect(AppConstants.apiBaseUrl, "http://dev.example:7999");
    });

    test("setActive persists and mutates AppConstants", () async {
      final prefs = await SharedPreferences.getInstance();
      final svc   = await ServerContextService.load(prefs);

      await svc.setActive(ServerContext.test);
      expect(svc.active, ServerContext.test);
      expect(AppConstants.apiBaseUrl, "http://test.example:8000");
      expect(AppConstants.wsBaseUrl,  "ws://test.example:8000");
      expect(prefs.getString("active_server_context"), "test");
    });

    test("reloading honors previously-stored selection", () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("active_server_context", "test");

      final svc = await ServerContextService.load(prefs);
      expect(svc.active, ServerContext.test);
    });
  });
}
