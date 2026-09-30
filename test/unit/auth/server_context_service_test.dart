import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/constants/app_constants.dart';
import 'package:lupin_mobile/services/auth/server_context_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests run against the SHIPPED `assets/config/server-contexts.json`, read
/// from disk, so a bad edit to the real file fails here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final shippedJson = File( "assets/config/server-contexts.json" ).readAsStringSync();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Inject the bundled asset for server-contexts.json.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler("flutter/assets", (message) async {
        final key = const StringCodec().decodeMessage(message);
        if (key == "assets/config/server-contexts.json") {
          return const StringCodec().encodeMessage(shippedJson);
        }
        return null;
      });
  });

  group("ServerContextService", () {
    test("loads all four contexts from the shipped JSON, in file order", () async {
      final prefs = await SharedPreferences.getInstance();
      final svc   = await ServerContextService.load(prefs);

      expect(svc.all.map((c) => c.id).toList(), ["dev", "test", "lan-dev", "lan-test"]);
      expect(svc.configFor("lan-dev").label,    "LAN DEV");
      expect(svc.configFor("lan-dev").baseUrl,  "http://192.168.1.21:7999");
      expect(svc.configFor("lan-dev").wsUrl,    "ws://192.168.1.21:7999");
      expect(svc.configFor("lan-test").label,   "LAN TEST");
      expect(svc.configFor("lan-test").baseUrl, "http://192.168.1.21:8000");
      expect(svc.configFor("lan-test").wsUrl,   "ws://192.168.1.21:8000");
    });

    test("load picks default context (dev, emulator) on first launch", () async {
      final prefs = await SharedPreferences.getInstance();
      final svc   = await ServerContextService.load(prefs);

      expect(svc.active, "dev");
      expect(svc.baseUrl, "http://10.0.2.2:7999");
      expect(svc.wsUrl,   "ws://10.0.2.2:7999");
      expect(AppConstants.apiBaseUrl, "http://10.0.2.2:7999");
      expect(AppConstants.wsBaseUrl,  "ws://10.0.2.2:7999");
    });

    test("setActive(lan-dev) persists and points AppConstants at the LAN address", () async {
      final prefs = await SharedPreferences.getInstance();
      final svc   = await ServerContextService.load(prefs);

      await svc.setActive("lan-dev");
      expect(svc.active, "lan-dev");
      expect(AppConstants.apiBaseUrl, "http://192.168.1.21:7999");
      expect(AppConstants.wsBaseUrl,  "ws://192.168.1.21:7999");
      expect(prefs.getString("active_server_context"), "lan-dev");
    });

    test("setActive(test) still works for the emulator test server", () async {
      final prefs = await SharedPreferences.getInstance();
      final svc   = await ServerContextService.load(prefs);

      await svc.setActive("test");
      expect(AppConstants.apiBaseUrl, "http://10.0.2.2:8000");
      expect(prefs.getString("active_server_context"), "test");
    });

    test("reloading honors previously-stored lan-dev selection", () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("active_server_context", "lan-dev");

      final svc = await ServerContextService.load(prefs);
      expect(svc.active, "lan-dev");
      expect(AppConstants.apiBaseUrl, "http://192.168.1.21:7999");
    });

    test("a stored id no longer in the JSON falls back to the default", () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("active_server_context", "gone");

      final svc = await ServerContextService.load(prefs);
      expect(svc.active, "dev");
    });

    test("setActive with an unknown id throws and changes nothing", () async {
      final prefs = await SharedPreferences.getInstance();
      final svc   = await ServerContextService.load(prefs);

      await expectLater(svc.setActive("nope"), throwsArgumentError);
      expect(svc.active, "dev");
      expect(prefs.getString("active_server_context"), isNull);
    });
  });
}
