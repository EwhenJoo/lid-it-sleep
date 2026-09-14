# Changelog

## 0.2.0

- Add an opt-in per-user background guard for closed-lid battery operation, including unplugging while the lid is already closed.
- Request S4 hibernation after a 10-second confirmation interval without relying on external-display disconnect reporting.
- Cancel on lid opening, AC reconnection or unknown sensor state; refresh lid observations after resume; bound retries and suppress repeated hibernation after a successful request.
- Build locally with the Windows .NET Framework compiler; install a limited-privilege logon task that continues on battery; provide status, local logs, observe-only mode and uninstall.
- Add 26 pure guard-policy tests. Existing 20 policy/diagnostic tests are retained. Automated tests never suspend the computer; physical unplug/resume validation remains device-specific.

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

