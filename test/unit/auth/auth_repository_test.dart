import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/services/auth/auth_repository.dart';

import '../../_helpers/fixture_loader.dart';

class _StubAdapter implements HttpClientAdapter {
  final List<RequestOptions> captured = [];
  final Map<String, ResponseBody Function(RequestOptions)> handlers;

  _StubAdapter(this.handlers);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future? cancelFuture,
  ) async {
    captured.add(options);
    final key     = "${options.method} ${options.path}";
    final handler = handlers[key];
    if (handler == null) {
      return ResponseBody.fromString("not found", 404);
    }
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonBody(Map<String, dynamic> body, {int status = 200}) {
  return ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  group("AuthRepository", () {
    late Dio dio;
    late _StubAdapter adapter;
    late AuthRepository repo;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: "http://test"));
      adapter = _StubAdapter({});
      dio.httpClientAdapter = adapter;
      repo = AuthRepository(dio);
    });

    test("login parses access + refresh tokens from the LoginResponse envelope", () async {
      // Loads a real backend response captured by src/scripts/capture-auth-fixtures.py
      // with sensitive fields redacted. If the backend shape drifts, re-run
      // the capture script and the regenerated fixture will fail tests that
      // made the old assumptions.
      adapter.handlers["POST /auth/login"] =
        (_) => jsonBodyFromFixture("auth/login_response.json");

      final tokens = await repo.login("a@b.com", "pw");
      expect(tokens.accessToken,  "fixture_access_token");
      expect(tokens.refreshToken, "fixture_refresh_token");
    });

    test("login throws AuthException (not raw TypeError) on missing tokens envelope", () async {
      // Legacy flat-shape response that the previous parser accepted. Now
      // must surface as a sensible AuthException so auth_bloc emits AuthError
      // instead of letting a raw TypeError bubble through.
      adapter.handlers["POST /auth/login"] = (_) => _jsonBody({
        "access_token"  : "acc-1",
        "refresh_token" : "ref-1",
      });

      await expectLater(
        repo.login("a@b.com", "pw"),
        throwsA(isA<AuthException>()
          .having((e) => e.message, "message", contains("missing 'tokens'"))),
      );
    });

    test("login 401 throws AuthException with statusCode", () async {
      adapter.handlers["POST /auth/login"] =
        (_) => jsonBodyFromFixture("auth/login_error_401.json", status: 401);

      await expectLater(
        repo.login("a@b.com", "pw"),
        throwsA(isA<AuthException>()
          .having((e) => e.statusCode, "statusCode", 401)
          .having((e) => e.message,    "message", "Invalid email or password")),
      );
    });

    test("refresh parses tokens from RefreshResponse envelope", () async {
      adapter.handlers["POST /auth/refresh"] =
        (_) => jsonBodyFromFixture("auth/refresh_response.json");

      final tokens = await repo.refresh("old-refresh");
      expect(tokens.accessToken,  "fixture_access_token");
      expect(tokens.refreshToken, "fixture_refresh_token");
    });

    test("refresh reuses old refresh_token if backend omits it", () async {
      adapter.handlers["POST /auth/refresh"] = (_) => _jsonBody({
        "message" : "Token refreshed successfully",
        "tokens"  : {
          "access_token" : "acc-2",
          "token_type"   : "bearer",
          "expires_in"   : 1800,
        },
      });

      final tokens = await repo.refresh("old-refresh");
      expect(tokens.accessToken,  "acc-2");
      expect(tokens.refreshToken, "old-refresh");
    });

    test("logout swallows 401 silently", () async {
      adapter.handlers["POST /auth/logout"] = (_) => _jsonBody(
        {"detail": "token expired"},
        status: 401,
      );

      await repo.logout("dead-token"); // should not throw
    });

    test("me returns AuthUser with id + email (from real UserResponse shape)", () async {
      adapter.handlers["GET /auth/me"] = (opts) {
        expect(opts.headers["Authorization"], "Bearer acc-1");
        return jsonBodyFromFixture("auth/me_response.json");
      };

      final user = await repo.me("acc-1");
      expect(user.id,    "uid-fixture");
      expect(user.email, "fixture@example.com");
    });
  });

  group("AuthTokens.fromJson", () {
    test("defaults tokenType to bearer", () {
      final t = AuthTokens.fromJson({
        "access_token"  : "a",
        "refresh_token" : "b",
      });
      expect(t.tokenType, "bearer");
    });
  });
}
