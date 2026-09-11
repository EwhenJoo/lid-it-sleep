# Changelog

## 0.1.1

- Standardize script filenames, the native API namespace, test paths and documentation on LidItSleep.
- Use `LidItSleep.ps1` and `Test-LidItSleep.ps1` as the entry points; update existing command shortcuts accordingly.
- Present Chinese and English documentation on the repository homepage with same-page language navigation.

## 0.1.0

- Read-only inspection of supported sleep states, stored lid actions and recent power events.
- Explicit sleep/hibernate lid configuration with preview, backup, readback and rollback attempt.
- Restore of the original lid values without importing an entire power plan.
- Event interpretation that separates screen-off sessions, confirmed sleep, thermal hibernation and standby energy-budget events.
- Chinese and English documentation; synthetic tests, no raw personal logs.

