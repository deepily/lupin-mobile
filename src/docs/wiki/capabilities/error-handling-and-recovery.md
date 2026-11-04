---
capability: error-handling-and-recovery
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.core.error_handling.error_handler.AppError@06e3af8651
  - lupin-mobile:lib.core.error_handling.error_handler.NetworkError@856efd01a6
  - lupin-mobile:lib.core.error_handling.error_handler.AuthError@ea148e65bc
  - lupin-mobile:lib.core.error_handling.error_handler.VoiceError@abe255aee8
  - lupin-mobile:lib.core.error_handling.error_handler.StorageError@02554002ca
  - lupin-mobile:lib.core.error_handling.error_handler.ValidationError@ba4bc42b84
  - lupin-mobile:lib.core.error_handling.error_handler.RecoveryStrategy@c8344b624d
  - lupin-mobile:lib.core.error_handling.error_handler.RecoveryAction@7414b1e74e
  - lupin-mobile:lib.core.error_handling.error_handler.ErrorHandlingResult@511c323373
  - lupin-mobile:lib.core.error_handling.error_handler.ErrorHandler@16b8bcba62
  - lupin-mobile:lib.core.error_handling.error_handler.ErrorInterceptor@4bc71cc371
  - lupin-mobile:lib.core.error_handling.error_handler.ErrorRecoveryProvider@315c132855
  - lupin-mobile:lib.core.error_handling.error_handler.NetworkErrorRecoveryProvider@38551558e9
  - lupin-mobile:lib.core.error_handling.error_handler.AuthErrorRecoveryProvider@27a7f0d5ab
  - lupin-mobile:lib.core.error_handling.error_handler.VoiceErrorRecoveryProvider@b45f3bd547
  - lupin-mobile:lib.core.error_handling.error_handler.StorageErrorRecoveryProvider@c27a347578
---
# Error handling and recovery

`ErrorHandler` captures uncaught Flutter and async errors, and turns any error into a user message plus recovery actions. `AppError` and its five subclasses are the typed errors it understands. Logging is in [[logging-and-redaction]].

## What it does
- `AppError` carries a stable `code`, a `message`, an optional `userMessage` and a timestamp. The subclasses are `NetworkError`, `AuthError`, `VoiceError`, `StorageError` and `ValidationError`, each with named factories such as `NetworkError.timeout()` and `ValidationError.invalid( field, value )`.
- `ErrorHandler.initialize()` installs `FlutterError.onError` and the platform dispatcher handler, and registers the default recovery providers. `AppInitialization` calls it.
- `ErrorHandler.handleError( error, stackTrace, context )` runs the interceptors in order, and the first one that returns `handled` wins. Otherwise it logs, picks a message and builds recovery actions.
- Log level follows the code: `NO_CONNECTION` and `TIMEOUT` warn, `SESSION_EXPIRED` and `INVALID_TOKEN` are info, everything else is an error.
- A recovery provider is looked up by the error's runtime type. With none, `NetworkError`, `AuthError` and `StorageError` get default actions: retry, sign in again, clear cache.
- A `RecoveryAction` has a `RecoveryStrategy` (`retry`, `fallback`, `refresh`, `reconnect`, `clearCache`, `restart` or none), a label and a callback.

## Don't
- Don't count on a default action doing the work. The retry, sign-in and clear-cache callbacks are empty, so the caller supplies the behavior.
- Don't expect crash reporting. `_reportCrash` only logs "Crash reported".
- Don't throw from an interceptor. A throw inside the handler returns `ErrorHandlingResult( handled: false )`.

## Invariants
- `handleError` never throws. Only the settings store builds one of these errors today (`ValidationError`), and no file outside the handler calls `handleError`.
