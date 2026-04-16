import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/services/auth/auth_token_provider.dart';

void main() {
  group("auth_token_provider", () {
    tearDown(() => clearAccessToken());

    test("starts null", () {
      expect(readAccessToken(), isNull);
    });

    test("set + read roundtrip", () {
      setAccessToken("abc");
      expect(readAccessToken(), "abc");
    });

    test("clear resets to null", () {
      setAccessToken("abc");
      clearAccessToken();
      expect(readAccessToken(), isNull);
    });
  });
}
