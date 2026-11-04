---
capability: settings-store
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.core.settings.settings_manager.SettingsCategory@f9e6903e7a
  - lupin-mobile:lib.core.settings.settings_manager.SettingType@83b4a98eca
  - lupin-mobile:lib.core.settings.settings_manager.SettingDefinition@eaf83f0ecd
  - lupin-mobile:lib.core.settings.settings_manager.SettingsManager@75952cfa44
  - lupin-mobile:lib.core.settings.settings_manager.SettingsChangedEvent@8d01d65c95
  - lupin-mobile:lib.core.settings.settings_service.SettingsService@0bda8aa063
  - lupin-mobile:lib.core.settings.settings_service.QuickSettingsPreset@09b2781509
  - lupin-mobile:lib.core.settings.settings_service.QuickSettingsPresetExtension@53a62d6cd3
  - lupin-mobile:lib.core.settings.settings_service.SettingsValidationIssue@1e01c25314
  - lupin-mobile:lib.core.settings.settings_service.SettingsValidationIssueType@19ad0a6c34
---
# Settings store

`SettingsManager` holds every user preference as a typed `SettingDefinition`, persists it through `StorageManager`, and announces changes. `SettingsService` is the typed facade the rest of the app is meant to call. Storage is in [[local-caches]].

## What it does
- Both classes are async singletons built with `getInstance()` and registered by [[app-bootstrap-and-di]]. Keys are dotted, such as `voice.enabled`, and are stored under `settings.<key>`.
- A definition carries a default, an optional range, an optional `allowedValues` list, an optional `validator`, `requiresRestart` and `isAdvanced`. `isValid` checks the range, the list and the validator.
- On start, `SettingsManager` loads every stored value and resets any invalid one to its default.
- `setSetting` validates, updates the cache, persists, then emits a `SettingsChangedEvent` on the `onSettingsChanged` stream. A persistence failure restores the old cached value and rethrows.
- `SettingsService` gives one getter and one setter per setting, plus `applyQuickPreset`, `validateSettings`, `importSettings` and the reset calls.
- `exportSettings` leaves out advanced settings. `importSettings` skips unknown keys and logs any value that fails validation.

## Don't
- Don't call `getSetting` with a key that has no definition. It throws `ArgumentError`, and `setSetting` does the same.
- Don't add a setting without a `SettingDefinition` in `_registerDefaultSettings`. A key outside that list can be neither read nor written.
- Don't expect `exportSettings` to round-trip advanced settings. They are never exported.

## Invariants
- A stored value that fails its definition never reaches a reader. It is replaced by the default at start.
- An invalid value passed to `setSetting` throws `ValidationError.invalid` and changes nothing.
- The event carries `requiresRestart`, but `hasChangesRequiringRestart` is a placeholder that always returns false.
- Outside the locator and the settings files, no file in `lib/` refers to either class today.
