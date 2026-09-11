# Contributing

欢迎中文或英文 Issue / PR。

Please distinguish stored settings from measured behavior and avoid describing a single successful test as a universal fix.

For a useful issue, include:

- Windows version, general laptop model and dock/display type (no serial numbers).
- Whether the cable also supplies power, and whether another charger remains connected.
- AC/DC lid actions read by the tool, plus the exact open/close/unplug sequence.
- A short, manually reviewed event summary showing whether `SleepEntered` was true, false or unavailable.
- Whether the problem occurs on a desk, and whether normal resume works.

Do not post full event logs, SleepStudy reports, computer names, usernames, serial numbers, credentials or precise activity history without reviewing and redacting them. Local backups and reports are ignored by Git. The sample tests contain fictional records only.

Run `./Test-LidItSleep.ps1` before submitting code. Tests must not change the host's power settings or put it to sleep. Keep hardware observations separate from mocked test results.
