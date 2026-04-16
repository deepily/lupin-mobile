import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/services/auth/auth_repository.dart';

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

    test("login parses access + refresh tokens", () async {
      adapter.handlers["POST /auth/login"] = (_) => _jsonBody({
        "access_token"  : "acc-1",
        "refresh_token" : "ref-1",
        "token_type"    : "bearer",
      });

      final tokens = await repo.login("a@b.com", "pw");
      expect(tokens.accessToken,  "acc-1");
      expect(tokens.refreshToken, "ref-1");
    });

    test("login 401 throws AuthException with statusCode", () async {
      adapter.handlers["POST /auth/login"] = (_) => _jsonBody(
        {"detail": "bad creds"},
        status: 401,
      );

      await expectLater(
        repo.login("a@b.com", "pw"),
        throwsA(isA<AuthException>()
          .having((e) => e.statusCode, "statusCode", 401)
          .having((e) => e.message,    "message", "bad creds")),
      );
    });

    test("refresh reuses old refresh_token if backend omits it", () async {
      adapter.handlers["POST /auth/refresh"] = (_) => _jsonBody({
        "access_token" : "acc-2",
        "token_type"   : "bearer",
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

    test("me returns AuthUser with id + email", () async {
      adapter.handlers["GET /auth/me"] = (opts) {
        expect(opts.headers["Authorization"], "Bearer acc-1");
        return _jsonBody({
          "id"    : 42,
          "email" : "a@b.com",
        });
      };

      final user = await repo.me("acc-1");
      expect(user.id,    "42");
      expect(user.email, "a@b.com");
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
