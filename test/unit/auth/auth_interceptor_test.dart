import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/services/auth/auth_interceptor.dart';
import 'package:lupin_mobile/services/auth/auth_repository.dart';
import 'package:lupin_mobile/services/auth/auth_token_provider.dart';

class _SequenceAdapter implements HttpClientAdapter {
  final List<ResponseBody Function(RequestOptions)> responses;
  final List<RequestOptions> captured = [];
  int _idx = 0;

  _SequenceAdapter(this.responses);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future? cancelFuture,
  ) async {
    captured.add(options);
    if (_idx >= responses.length) {
      return ResponseBody.fromString("no more responses", 500);
    }
    return responses[_idx++](options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, dynamic> body, {int status = 200}) {
  return ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
  );
}

void main() {
  group("AuthInterceptor", () {
    late Dio dio;
    late _SequenceAdapter adapter;
    late AuthRepository repo;
    late List<AuthTokens> rotated;
    late int refreshFailedCount;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: "http://test"));
      rotated = [];
      refreshFailedCount = 0;
      clearAccessToken();
    });

    tearDown(() => clearAccessToken());

    test("injects Bearer when access token is set", () async {
      setAccessToken("acc-1");
      adapter = _SequenceAdapter([(_) => _json({"ok": true})]);
      dio.httpClientAdapter = adapter;
      repo = AuthRepository(dio);
      dio.interceptors.add(AuthInterceptor(
        dio              : dio,
        repo             : repo,
        readRefreshToken : () async => null,
        onTokensRotated  : (t) async {},
        onRefreshFailed  : () async {},
      ));

      await dio.get("/api/whatever");
      expect(adapter.captured.single.headers["Authorization"], "Bearer acc-1");
    });

    test("skips injection for /auth/login and /auth/refresh", () async {
      setAccessToken("acc-1");
      adapter = _SequenceAdapter([
        (_) => _json({"ok": 1}),
        (_) => _json({"ok": 2}),
      ]);
      dio.httpClientAdapter = adapter;
      repo = AuthRepository(dio);
      dio.interceptors.add(AuthInterceptor(
        dio              : dio,
        repo             : repo,
        readRefreshToken : () async => null,
        onTokensRotated  : (t) async {},
        onRefreshFailed  : () async {},
      ));

      await dio.post("/auth/login",   data: {});
      await dio.post("/auth/refresh", data: {});
      expect(adapter.captured[0].headers.containsKey("Authorization"), isFalse);
      expect(adapter.captured[1].headers.containsKey("Authorization"), isFalse);
    });

    test("401 triggers refresh and retries original request", () async {
      setAccessToken("stale");
      adapter = _SequenceAdapter([
        // 1) original /api/me → 401
        (_) => _json({"detail": "expired"}, status: 401),
        // 2) /auth/refresh → rotated tokens
        (_) => _json({
          "access_token"  : "fresh",
          "refresh_token" : "new-ref",
        }),
        // 3) retried /api/me → 200
        (opts) {
          expect(opts.headers["Authorization"], "Bearer fresh");
          return _json({"ok": true});
        },
      ]);
      dio.httpClientAdapter = adapter;
      repo = AuthRepository(dio);
      dio.interceptors.add(AuthInterceptor(
        dio              : dio,
        repo             : repo,
        readRefreshToken : () async => "old-ref",
        onTokensRotated  : (t) async => rotated.add(t),
        onRefreshFailed  : () async => refreshFailedCount++,
      ));

      final res = await dio.get("/api/me");
      expect(res.statusCode, 200);
      expect(rotated.single.accessToken,  "fresh");
      expect(rotated.single.refreshToken, "new-ref");
      expect(readAccessToken(), "fresh");
      expect(refreshFailedCount, 0);
    });

    test("401 with missing refresh token invokes onRefreshFailed and bubbles", () async {
      setAccessToken("stale");
      adapter = _SequenceAdapter([
        (_) => _json({"detail": "expired"}, status: 401),
      ]);
      dio.httpClientAdapter = adapter;
      repo = AuthRepository(dio);
      dio.interceptors.add(AuthInterceptor(
        dio              : dio,
        repo             : repo,
        readRefreshToken : () async => null,
        onTokensRotated  : (t) async {},
        onRefreshFailed  : () async => refreshFailedCount++,
      ));

      await expectLater(
        dio.get("/api/me"),
        throwsA(isA<DioException>()),
      );
      expect(refreshFailedCount, 1);
    });

    test("does not retry twice (one refresh attempt per request)", () async {
      setAccessToken("stale");
      adapter = _SequenceAdapter([
        (_) => _json({"detail": "expired"}, status: 401), // original
        (_) => _json({
          "access_token"  : "fresh",
          "refresh_token" : "new-ref",
        }),                                                // refresh
        (_) => _json({"detail": "still 401"}, status: 401), // retry still fails
      ]);
      dio.httpClientAdapter = adapter;
      repo = AuthRepository(dio);
      dio.interceptors.add(AuthInterceptor(
        dio              : dio,
        repo             : repo,
        readRefreshToken : () async => "old-ref",
        onTokensRotated  : (t) async => rotated.add(t),
        onRefreshFailed  : () async => refreshFailedCount++,
      ));

      await expectLater(
        dio.get("/api/me"),
        throwsA(isA<DioException>()),
      );
      // 3 fetches total: original + refresh + retry. No 4th.
      expect(adapter.captured.length, 3);
    });
  });
}
