---
capability: logging-and-redaction
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.core.logging.error_summary.describeFailure@b31c9f692d
  - lupin-mobile:lib.core.logging.log_file_store.LogFileStore@f19760f1d0
  - lupin-mobile:lib.core.logging.log_redaction.redactSecrets@37a86ddd4c
  - lupin-mobile:lib.core.logging.logger.LogLevel@34841922b1
  - lupin-mobile:lib.core.logging.logger.LogContext@ffc5637eb9
  - lupin-mobile:lib.core.logging.logger.LogEntry@69fbad1c8d
  - lupin-mobile:lib.core.logging.logger.LogDestination@d7e205477e
  - lupin-mobile:lib.core.logging.logger.ConsoleLogDestination@a3d6987277
  - lupin-mobile:lib.core.logging.logger.FileLogDestination@a150fff58d
  - lupin-mobile:lib.core.logging.logger.RemoteLogDestination@1136787a56
  - lupin-mobile:lib.core.logging.logger.Logger@ad8ac5179d
  - lupin-mobile:lib.core.logging.logger.TaggedLogger@cca31c8816
---
# Logging and redaction

`Logger` is the one logging entry point. It sends leveled entries to pluggable destinations and masks credentials in every message before any destination sees it. `redactSecrets` and `describeFailure` are the two helpers that keep secrets and user text out of logs. See [[error-handling-and-recovery]].

## What it does
- `Logger.initialize` sets the minimum `LogLevel` and adds the console, file and remote destinations. `Logger.tagged( "Name" )` returns a `TaggedLogger` that prefixes a tag.
- Levels are `verbose`, `debug`, `info`, `warning`, `error` and `critical`. The console shows everything in debug builds and warnings and above in release.
- `Logger.setGlobalContext( LogContext )` stamps user id, session id and feature on later entries.
- `FileLogDestination` buffers 100 entries and flushes at once on `error` and above. At 10 MB it rotates and keeps 5 files. The buffer holds at most 1000 entries and the oldest drop first.
- The file destination writes through `LogFileStore`, which `StorageManager` implements. The interface keeps `logger.dart` free of storage imports.
- `redactSecrets( line )` masks JWTs, `Authorization` values and values of fields named like `token`, `password`, `secret` or `api_key`. Count fields such as `max_tokens` keep their numbers.
- `describeFailure( error )` returns the type, plus the offset for a `FormatException`, and never the message.

## Don't
- Don't log a `FormatException` message. It quotes the text it failed to parse, which can be stored user content. Use `describeFailure`.
- Don't print request headers or bodies outside debug builds. `HttpService` adds its `LogInterceptor` only when `kDebugMode`, sends no headers, and wraps the output in `redactSecrets`.
- Don't call `Logger.resetForTesting` outside tests.

## Invariants
- `redactSecrets` masks with `<redacted>`. The logger applies it to the message, tag, error text, stack trace and every context field.
- A credential reaches logcat only if two of three controls fail: debug-only registration, no headers logged, and redaction.
