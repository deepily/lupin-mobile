import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/services/network/http_service.dart';

/// Regression: `HttpService._configureDio()` must be idempotent on a shared
/// Dio. Without the guard, `CachedHttpService` (which extends HttpService)
/// would re-add LogInterceptor + InterceptorsWrapper on the same singleton
/// Dio from DI, producing 2× log output per request and making every HTTP
/// call look like a duplicate dispatch in logcat.
void main() {
  group( "HttpService._configureDio", () {
    test( "is idempotent on a shared Dio (second instance adds no interceptors)", () {
      final dio = Dio();
      final before = dio.interceptors.length;

      HttpService( dio );
      final afterFirst  = dio.interceptors.length;
      final addedFirst  = afterFirst - before;

      HttpService( dio ); // e.g. CachedHttpService super(dio) on same Dio
      final afterSecond = dio.interceptors.length;

      // First construction adds LogInterceptor + InterceptorsWrapper = 2.
      expect( addedFirst,  2 );
      // Second construction must add nothing — the guard short-circuits.
      expect( afterSecond, afterFirst );
    });

    test( "different Dios configure independently", () {
      final dioA = Dio();
      final dioB = Dio();
      final beforeA = dioA.interceptors.length;
      final beforeB = dioB.interceptors.length;

      HttpService( dioA );
      HttpService( dioB );

      // Each fresh Dio gets its own 2-interceptor configuration.
      expect( dioA.interceptors.length - beforeA, 2 );
      expect( dioB.interceptors.length - beforeB, 2 );
    });
  });
}
