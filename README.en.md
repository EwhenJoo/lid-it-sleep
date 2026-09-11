# lid-it-sleep

**Windows lid power-policy configuration and sleep diagnostics.**

[简体中文](README.md) | English · [MIT License](LICENSE)

`lid-it-sleep` supports using a laptop with its lid closed and an external display, then disconnecting it for transport. It provides power-policy inspection, lid-action configuration and sleep-event analysis. By separating stored settings, screen-off sessions and reported sleep, it helps users verify actual device behavior.

## Features

- **Read-only inspection:** available sleep states, the active plan's lid policy and recent power events.
- **Policy configuration:** separate lid actions for battery and external power.
- **Reversible changes:** `-WhatIf` preview, backups, readback verification and rollback on failure.
- **Event interpretation:** distinguish screen-off, modern standby, hibernation requests, thermal protection and unexpected restarts.
- **Local operation:** no service, background process, telemetry or network functionality.

## Requirements

| Component | Requirement or verification status |
| --- | --- |
| Operating system | Windows; read-only functionality verified on Windows 11 25H2 |
| PowerShell 7 | Runtime verification and 20 mocked tests passed on 7.6.5 |
| Windows PowerShell 5.1 | Syntax checks passed; runtime verification pending |
| Write permissions | Depend on system permissions and organization policy; elevation may be required |
| Hibernation | Must already be supported and enabled before selecting `Hibernate` |

Sleep states are determined by device firmware and Windows. Modern standby uses S0 low-power idle; hibernation uses S4. The tool does not convert S0 into traditional S3 sleep.

## Quick start

Download and extract the source, then open PowerShell in the project directory:

```powershell
# Default mode: read-only inspection
.\ClamshellSleep.ps1

# Inspect the latest 12 power events within one day
.\ClamshellSleep.ps1 -Days 1 -MaxEvents 12
```

If Windows blocks downloaded scripts, review the source and follow your organization's execution policy. The tool does not modify script execution policy.

### Configure lid actions

This example selects Sleep for both external power and battery. Preview first, then apply as needed:

```powershell
.\ClamshellSleep.ps1 -Mode Apply -BatteryAction Sleep -PluggedInAction Sleep -WhatIf
.\ClamshellSleep.ps1 -Mode Apply -BatteryAction Sleep -PluggedInAction Sleep
```

An alternative selects Hibernate on battery while retaining Sleep on external power:

```powershell
.\ClamshellSleep.ps1 -Mode Apply -BatteryAction Hibernate -PluggedInAction Sleep -WhatIf
.\ClamshellSleep.ps1 -Mode Apply -BatteryAction Hibernate -PluggedInAction Sleep
```

If Sleep on external power interrupts external-display use, select `-PluggedInAction DoNothing`. This changes AC lid behavior and may disengage input suppression; consider [Microsoft's input-suppression documentation](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/power-controls-enableinputsuppression).

### Restore previous settings

Before each actual change, the tool saves the previous lid policy to a unique JSON file in `backups/` and prints its path. Substitute that path for the placeholder below:

```powershell
.\ClamshellSleep.ps1 -Mode Restore -BackupPath .\backups\lid-policy-YOUR-BACKUP-ID.json -WhatIf
.\ClamshellSleep.ps1 -Mode Restore -BackupPath .\backups\lid-policy-YOUR-BACKUP-ID.json
```

Manually select the backup's original power plan before restoring. Restore also backs up the current values. If a write fails, the tool attempts rollback and retains the backup. If the requested values already match, no write or backup occurs.

## Parameters

| Parameter | Values | Default | Description |
| --- | --- | --- | --- |
| `-Mode` | `Inspect`, `Apply`, `Restore` | `Inspect` | Inspect, configure or restore |
| `-BatteryAction` | `Sleep`, `Hibernate` | `Sleep` | Battery lid action in Apply mode |
| `-PluggedInAction` | `Sleep`, `DoNothing` | `Sleep` | AC lid action in Apply mode |
| `-BackupPath` | JSON file path | None | Required in Restore mode |
| `-Days` | 1–90 | 7 | Event lookback period |
| `-MaxEvents` | 1–200 | 24 | Maximum number of returned events |
| `-WhatIf` | Switch | Off | Preview configuration or restore without writing settings or backups |

## Event interpretation

The tool reads structured XML fields from `Microsoft-Windows-Kernel-Power`, independently of localized event descriptions. Times use the local time zone; events are shown newest first.

| Event or field | Meaning | Interpretation boundary |
| --- | --- | --- |
| 506 | Modern standby session begins | Does not independently prove low-power sleep |
| 507, `SleepEntered=true` | The session reports having entered sleep | SleepSeconds is the session's reported sleep duration |
| 507, `SleepEntered=false` | The session does not report entering sleep | Distinguish from screen-off activity; a missing field is unknown |
| 42, `TargetState=5` | S4 hibernation requested | 5 is a Windows enum value; a request does not prove completion |
| 88 | Thermal hibernation event | Analyze separately from normal standby |
| 41 | Unexpected restart | Does not establish the cause |
| 506/507, reason 55 | Standby energy-budget policy event | Not independent evidence of overheating or a screen-on wake |

Windows 11 modern standby can restrict most wake sources after detecting excessive drain. Adjacent exit/entry records at the same time may reflect a standby policy transition and should be interpreted alongside other fields. [Microsoft: modern standby wake sources](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/modern-standby-wake-sources)

`-MaxEvents` can truncate sessions. Individual events do not replace a complete sleep-session analysis.

## Workflow validation

1. On a ventilated desk, close the lid while using an external display and confirm normal operation.
2. Disconnect as usual and check whether this also switches the laptop to battery power.
3. Wait approximately one minute, open the lid and briefly press the power button if needed to check resume behavior.
4. Run the read-only inspection and review power states, event times and resume reasons.

For longer power-consumption analysis, generate a SleepStudy report in an elevated terminal:

```powershell
powercfg /sleepstudy /output sleepstudy.html
```

Reports may contain device, application and activity information; review and redact them before sharing. Allow an unusually hot device to cool before further testing in a ventilated location.

## Scope

The tool changes only the active power plan's two lid-action values. It does not configure power buttons, timeouts, networking, wake devices, BIOS or security settings.

It does not monitor Thunderbolt or USB-C disconnect events. Windows documents re-evaluation of the battery lid policy in certain closed-lid unplug scenarios, but actual results depend on hardware, drivers, power sources and system policy. Whether unplugging with an already closed lid triggers the intended sleep or hibernation must be tested on the target device. Organization policies or vendor utilities may override saved settings.

## Testing and validation

```powershell
.\Test-ClamshellSleep.ps1
```

The 20 automated tests use synthetic events and mocked power interfaces. They cover event interpretation, validation, previews, backups, restore, idempotence and rollback without modifying real power settings.

| Validation | Current result |
| --- | --- |
| PowerShell 7 tests | All 20 passed |
| Windows PowerShell 5.1 | Syntax checks passed; local execution policy blocked runtime testing |
| Live inspection | Verified on one Windows 11 25H2 device |
| Configuration writes and restore | Mocked tests passed; real writes have not been verified |
| Hardware sleep behavior | One approximately 39-minute modern standby observation resumed on lid opening with about 0.44 percentage points of battery loss |

The observed device had `Sleep` stored for both AC and battery lid actions. One observation is not a universal compatibility or repair guarantee and does not establish that a particular configuration caused an improvement. Original personal logs are not included.

## Contributing and license

Redacted reproduction steps and code improvements are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting.

Licensed under the [MIT License](LICENSE).

## References

- [Lid action values](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/power-button-and-lid-settings-lid-switch-close-action)
- [Input suppression and closed-lid unplug behavior](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/power-controls-enableinputsuppression)
- [Modern standby wake sources and drain protection](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/modern-standby-wake-sources)
- [SleepStudy](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/modern-standby-sleepstudy)
- [powercfg commands](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options)
