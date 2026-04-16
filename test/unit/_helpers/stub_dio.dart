import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Test Dio adapter that returns canned responses keyed by `"METHOD path"`.
/// Captures all RequestOptions for query/body inspection.
class StubAdapter implements HttpClientAdapter {
  final Map<String, ResponseBody Function(RequestOptions)> handlers;
  final List<RequestOptions> captured = [];

  StubAdapter([Map<String, ResponseBody Function(RequestOptions)>? handlers])
      : handlers = handlers ?? {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future? cancelFuture,
  ) async {
    captured.add(options);
    final key = "${options.method} ${options.path}";
    final h   = handlers[key];
    if (h == null) {
      return ResponseBody.fromString(
        jsonEncode({"detail": "no stub for $key"}),
        404,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }
    return h(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(dynamic body, {int status = 200}) {
  return ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
  );
}

Dio makeDio(StubAdapter adapter, {String baseUrl = "http://test"}) {
  final dio = Dio(BaseOptions(baseUrl: baseUrl));
  dio.httpClientAdapter = adapter;
  return dio;
}
