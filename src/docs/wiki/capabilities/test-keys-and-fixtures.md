---
capability: test-keys-and-fixtures
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.core.testing.test_keys.TestKeys@21ede3e1fe
---
# Test keys

`TestKeys` is the one list of widget keys that the app and its tests share. A key is a plain string constant, so a test finds a widget without depending on its text or position. See [[theme-and-shared-widgets]] for the footer that carries one.

## What it does
- Each constant is a string such as `login.email` or `server_context.toggle`, grouped by screen in `lib/core/testing/test_keys.dart`.
- Production code attaches a key with `Key( TestKeys.loginEmailField )`. Tests look it up with `find.byKey( Key( TestKeys.loginEmailField ) )`.
- A name ending in `Prefix` is a stem for a list item. The use site adds a suffix, such as `${inboxSenderTilePrefix}s-1` for one sender tile.
- Forms follow a pattern of one short prefix per form, so keys from different forms do not clash. The podcast form uses `pg`, the presentation form `px`, research to podcast `rp` and research to presentation `rx`.
- The class has a private constructor and only static constants. It holds no logic.

## Don't
- Don't find a widget by its text in a test. Text changes with copy and language, and a key does not.
- Don't build a key from a literal string at the use site. Add a constant here and use it in both places.
- Don't reuse a prefix for two lists. The suffix is the only thing that tells two items apart.

## Invariants
- A key string is unique across the file.
- A prefix constant is never used as a complete key. It always takes a suffix.
- Tests under `test/` are the main readers. 91 files under `test/` refer to `TestKeys`.
