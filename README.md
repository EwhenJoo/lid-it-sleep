# lid-it-sleep

**Windows 合盖拔电源自动睡眠、电源策略配置与睡眠诊断。**  
**Closed-lid unplug sleep guard, lid power policies and sleep diagnostics for Windows.**

[简体中文](#简体中文) | [English](#english) · [MIT License](LICENSE)

## 简体中文

[English ↓](#english)

`lid-it-sleep` 面向合盖使用外接显示器、断开连接后携带笔记本的场景，提供电源策略检查、合盖动作配置和睡眠事件分析。通过区分配置值、熄屏会话与实际睡眠记录，帮助用户验证设备是否按预期进入睡眠或休眠。

### 功能

- **只读检查**：查看可用睡眠状态、活动电源方案的合盖策略及近期电源事件。
- **策略配置**：分别设置电池和外接电源供电时的合盖动作。
- **可恢复修改**：支持 `-WhatIf` 预览、修改前备份、写入后校验和失败回滚。
- **事件分析**：区分熄屏、现代待机、休眠请求、热保护和异常重启。
- **拔电源保护（可选安装）**：合盖且电池供电持续 10 秒后主动请求睡眠，无需再次开合盖子。
- **本地运行**：检查工具运行后退出；保护器安装后随用户登录常驻，不包含遥测或联网功能。

### 环境要求

| 项目 | 要求或验证状态 |
| --- | --- |
| 操作系统 | Windows；已在 Windows 11 25H2 上验证只读功能 |
| PowerShell 7 | 7.6.5 已通过运行验证和 20 项模拟测试 |
| Windows PowerShell 5.1 | 已通过语法检查，尚未完成运行验证 |
| 修改权限 | 取决于系统权限与组织策略；写入可能需要管理员终端 |
| 休眠配置 | 选择 `Hibernate` 前，系统必须已支持并启用休眠 |

睡眠类型由设备固件和 Windows 决定。现代待机使用 S0 低功耗空闲，休眠使用 S4。工具不会将 S0 转换为传统 S3 睡眠。

### 快速开始

#### 安装合盖拔电源保护器

原有 `LidItSleep.ps1 -Mode Apply` 只保存合盖策略，并不会启动后台监听。要覆盖“已经合盖，再拔掉供电雷电线”的流程，需要安装保护器：

```powershell
.\Install-Guard.ps1 -WhatIf       # 预览安装
.\Install-Guard.ps1               # 编译、安装、注册登录任务并立即启动
.\Install-Guard.ps1 -Mode Status  # 查看任务、实时盖子/供电状态及日志
```

安装使用 Windows 自带的 .NET Framework 4.x 编译器，无需下载依赖。若创建计划任务被拒绝，请在同一 Windows 账户的管理员 PowerShell 中运行安装命令。任务本身以该用户的普通权限运行，不使用 SYSTEM，也不改变执行策略。安装器会解析真实文件路径，以兼容打包终端的目录重定向，并验证任务与进程均已启动。若目录由终端应用管理，卸载该终端后应重新安装保护器。

保护器直接接收 Windows 盖子状态通知，每秒复核电源状态。在确认**电池供电且合盖持续 10 秒**后调用 `SetSuspendState(false, false, false)` 主动请求睡眠，不请求休眠、不禁用唤醒事件，也不以休眠作为失败后的替代动作。开盖、重新接电或传感器状态未知都会取消倒计时。开盖用电池、合盖接电均不会触发。启动时已经合盖用电池、用电池时再次合盖也会受到保护。

外接显示器状态不参与判断，因此不会因其断开状态迟报而漏掉本场景。这也意味着：**合盖使用外屏但只有电池供电时同样会睡眠**；若另有充电器维持接电，单独拔视频线不会触发。

日志位于 `%LOCALAPPDATA%\LidItSleep\state\guard.log`，实时状态位于同目录 `status.txt`。日志会轮转。保护器退出后状态文件会保留，因此需结合任务状态、PID 和 `Updated` 时间确认仍在运行。无人登录或用户已注销时不运行。保护器不要求启用休眠。Windows 若先进入睡眠，普通用户后台进程可能暂停；保护器用于处理仍在运行却未睡眠的情况。传感器未知时不会猜测合盖。系统挂死、驱动未报告真实盖子状态或拒绝睡眠时，软件无法保证进入低功耗状态；最多进行三次失败重试，每次至少间隔 60 秒。API 返回成功也不等于已验证进入低功耗睡眠。

```powershell
.\Install-Guard.ps1 -Mode Uninstall # 停止保护器、移除登录任务；保留文件和日志
```

保护器不更改现有合盖策略。首次安装后，在通风桌面上验证合盖拔供电线、10 秒内重新接电取消、开盖用电池不触发，以及睡眠后的恢复。

#### 只读诊断

下载并解压源码，在项目目录打开 PowerShell：

```powershell
# 默认模式：只读检查
.\LidItSleep.ps1

# 查看最近一天的 12 条电源事件
.\LidItSleep.ps1 -Days 1 -MaxEvents 12
```

若系统阻止执行下载的脚本，请先审阅源码，并遵循所在组织的执行策略。工具不会更改脚本执行策略。

#### 配置合盖动作

以下示例将接电和电池供电时的合盖动作都设为睡眠。先预览，再按需应用：

```powershell
.\LidItSleep.ps1 -Mode Apply -BatteryAction Sleep -PluggedInAction Sleep -WhatIf
.\LidItSleep.ps1 -Mode Apply -BatteryAction Sleep -PluggedInAction Sleep
```

可选配置：使用电池时合盖进入休眠，接电时保留睡眠动作。

```powershell
.\LidItSleep.ps1 -Mode Apply -BatteryAction Hibernate -PluggedInAction Sleep -WhatIf
.\LidItSleep.ps1 -Mode Apply -BatteryAction Hibernate -PluggedInAction Sleep
```

如果接电合盖设为睡眠会中断外接显示器的使用，可选择 `-PluggedInAction DoNothing`。该选项会改变接电合盖行为，并可能使输入抑制不再生效；请结合[微软关于输入抑制的说明](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/power-controls-enableinputsuppression)评估。

#### 恢复原设置

每次实际修改前，工具会将原合盖策略保存为 `backups/` 中的唯一 JSON 文件，并打印路径。用实际路径替换下面的占位文件名：

```powershell
.\LidItSleep.ps1 -Mode Restore -BackupPath .\backups\lid-policy-YOUR-BACKUP-ID.json -WhatIf
.\LidItSleep.ps1 -Mode Restore -BackupPath .\backups\lid-policy-YOUR-BACKUP-ID.json
```

恢复前需手动选中备份对应的电源方案。恢复操作也会备份当前值；若写入失败，工具会尝试回滚并保留备份。若目标配置与当前值一致，则不写入也不生成备份。

### 参数

| 参数 | 可选值 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `-Mode` | `Inspect`、`Apply`、`Restore` | `Inspect` | 检查、配置或恢复 |
| `-BatteryAction` | `Sleep`、`Hibernate` | `Sleep` | Apply 模式下的电池合盖动作 |
| `-PluggedInAction` | `Sleep`、`DoNothing` | `Sleep` | Apply 模式下的接电合盖动作 |
| `-BackupPath` | JSON 文件路径 | 无 | Restore 模式必填 |
| `-Days` | 1–90 | 7 | 检查事件的时间范围 |
| `-MaxEvents` | 1–200 | 24 | 返回的最大事件数 |
| `-WhatIf` | 开关 | 关闭 | 预览配置或恢复，不写入设置或备份 |

### 事件解读

工具读取 `Microsoft-Windows-Kernel-Power` 的结构化 XML 字段，不依赖事件描述的显示语言。时间采用本机时区，事件按新到旧排列。

| 事件或字段 | 含义 | 解读范围 |
| --- | --- | --- |
| 506 | 现代待机会话开始 | 不能单独证明已进入低功耗睡眠 |
| 507，`SleepEntered=true` | 会话报告实际进入过睡眠 | SleepSeconds 为该会话报告的睡眠时长 |
| 507，`SleepEntered=false` | 会话未报告进入睡眠 | 与仅熄屏区分；字段缺失时显示未知 |
| 42，`TargetState=5` | 请求进入休眠 S4 | 5 是 Windows 枚举值；请求不等于完成 |
| 88 | 热保护休眠事件 | 与普通待机事件分别分析 |
| 41 | 异常重启 | 不能单独确定重启原因 |
| 506/507，原因 55 | 待机耗电预算策略事件 | 不是独立的过热证据，也不等同于亮屏唤醒 |

Windows 11 的现代待机可在检测到过量耗电后限制大多数唤醒来源。同一时刻出现的退出和进入记录可能反映待机策略切换，应结合其他字段分析。[微软：现代待机唤醒来源](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/modern-standby-wake-sources)

`-MaxEvents` 可能截断会话；单条事件不能替代完整的睡眠时段分析。

### 工作流验证

1. 在通风桌面上，合盖连接外接显示器，确认工作状态正常。
2. 按日常流程断开连接，并确认是否同时切换到电池供电。
3. 等待约一分钟后开盖，必要时短按电源键，检查能否正常恢复。
4. 运行只读检查，核对进入的电源状态、事件时间和恢复原因。

如需分析长时间待机功耗，可在管理员终端生成 SleepStudy 报告：

```powershell
powercfg /sleepstudy /output sleepstudy.html
```

报告可能包含设备、应用和活动时间信息，分享前请审阅并脱敏。明显发热的设备应先散热，再在通风条件下测试。

### 适用范围

`LidItSleep.ps1` 仅修改活动电源方案的两项合盖动作，不调整电源按键、超时、网络、唤醒设备、BIOS 或安全设置。另行安装的保护器提供后台状态监听和主动睡眠请求。

保护器监听盖子和供电状态，不识别具体雷电/USB-C 接口，也不依赖外屏状态。仅保存合盖策略无法保证已合盖时拔线触发睡眠。保护器通过单独请求睡眠补足这一行为，不请求 S4；实际拔线与恢复仍需在目标设备上验证。组织策略或厂商软件可能覆盖设置或阻止请求。

### 测试与验证

```powershell
.\Test-LidItSleep.ps1
.\Test-Guard.ps1
.\Build-Guard.ps1
# 仅观察真实传感器，不发出睡眠请求；60 秒后退出
.\build\LidItSleep.Guard.exe --observe --seconds 60 --state-dir .\test-output
```

20 项原有测试使用虚构事件和模拟电源接口，覆盖事件解释和策略修改。30 项新增保护器测试覆盖拔电源、取消、未知状态、恢复、重试和重复触发抑制。测试不修改真实电源设置，也不请求真实睡眠或休眠。

| 验证项目 | 当前结果 |
| --- | --- |
| PowerShell 7 测试 | 原有 20 项及保护器 30 项通过 |
| Windows PowerShell 5.1 | 语法检查通过；本机执行策略阻止运行，运行兼容性尚待验证 |
| 实时读取 | 在一台 Windows 11 25H2 设备上通过 |
| 配置写入与恢复 | 已通过模拟测试，尚未进行真实写入验证 |
| 硬件睡眠行为 | 一次约 39 分钟的现代待机观察正常开盖恢复，电量下降约 0.44 个百分点 |

该观察时读取到的接电和电池合盖动作均为 `Sleep`。单次观察不构成通用兼容性或故障修复保证，也不能证明行为改善由特定配置引起。仓库不包含原始个人日志。

### 贡献与许可

欢迎提交经过脱敏的复现步骤和代码改进。提交前请阅读[贡献说明](CONTRIBUTING.md)。

本项目采用 [MIT License](LICENSE)。

### 参考资料

- [合盖动作的取值](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/power-button-and-lid-settings-lid-switch-close-action)
- [输入抑制与合盖拔电源行为](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/power-controls-enableinputsuppression)
- [现代待机唤醒与耗电保护](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/modern-standby-wake-sources)
- [SleepStudy](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/modern-standby-sleepstudy)
- [powercfg 命令](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options)

---

## English

[简体中文 ↑](#简体中文)

`lid-it-sleep` supports using a laptop with its lid closed and an external display, then disconnecting it for transport. It provides power-policy inspection, lid-action configuration and sleep-event analysis. By separating stored settings, screen-off sessions and reported sleep, it helps users verify actual device behavior.

### Features

- **Read-only inspection:** available sleep states, the active plan's lid policy and recent power events.
- **Policy configuration:** separate lid actions for battery and external power.
- **Reversible changes:** `-WhatIf` preview, backups, readback verification and rollback on failure.
- **Event interpretation:** distinguish screen-off, modern standby, hibernation requests, thermal protection and unexpected restarts.
- **Optional unplug guard:** actively request sleep after 10 seconds of closed-lid battery operation, without reopening the lid.
- **Local operation:** inspection exits after running; the optional guard runs in the background at user logon. No telemetry or network functionality.

### Requirements

| Component | Requirement or verification status |
| --- | --- |
| Operating system | Windows; read-only functionality verified on Windows 11 25H2 |
| PowerShell 7 | Runtime verification and 20 mocked tests passed on 7.6.5 |
| Windows PowerShell 5.1 | Syntax checks passed; runtime verification pending |
| Write permissions | Depend on system permissions and organization policy; elevation may be required |
| Hibernation | Must already be supported and enabled before selecting `Hibernate` |

Sleep states are determined by device firmware and Windows. Modern standby uses S0 low-power idle; hibernation uses S4. The tool does not convert S0 into traditional S3 sleep.

### Quick start

#### Install the closed-lid unplug guard

`LidItSleep.ps1 -Mode Apply` only saves lid policies. It does not start a background listener. Install the guard to handle unplugging a power-supplying Thunderbolt cable while the lid is already closed:

```powershell
.\Install-Guard.ps1 -WhatIf       # Preview
.\Install-Guard.ps1               # Build, install, register logon task and start
.\Install-Guard.ps1 -Mode Status  # Task, current sensor state and recent logs
```

Builds locally using the Windows .NET Framework 4.x compiler, without dependency downloads. If task registration is denied, run installation in an elevated PowerShell under the same Windows account. The task itself runs with that user's limited privileges, not SYSTEM. Execution policies are not changed. The installer resolves physical file paths to handle packaged-terminal redirection and verifies both task and process startup. Reinstall the guard after removing a terminal app that owns its redirected install directory.

The guard receives Windows lid notifications and checks current power once per second. After **10 continuous seconds on battery with the lid closed**, it calls `SetSuspendState(false, false, false)` to request sleep. It does not request hibernation, disable wake events or fall back to hibernation on failure. Opening the lid, reconnecting power or unknown sensor values cancels the countdown. Battery use with an open lid and AC use with a closed lid do not trigger it. Starting the guard already closed on battery, or subsequently closing the lid on battery, is also covered.

External-display state is deliberately excluded because disconnect reporting can lag. Consequently, **closed-lid external-display use on battery also triggers sleep**. Disconnecting only a video cable while another charger supplies power does not trigger the guard.

Rotating logs: `%LOCALAPPDATA%\LidItSleep\state\guard.log`; live state: `status.txt` in the same folder. Status files remain after exit: verify the task, PID and `Updated` time as well. The guard requires a logged-on user, but does not require hibernation to be enabled. If Windows sleeps first, it may suspend the user process. It addresses the case where the computer keeps running instead of sleeping. Unknown lid state does not authorize a request. It cannot guarantee low-power sleep if Windows hangs, firmware reports incorrect lid state or a request is rejected. Failed requests retry at most three times per interval with at least 60 seconds between attempts. API acceptance is not proof of low-power sleep.

```powershell
.\Install-Guard.ps1 -Mode Uninstall # Stop and remove logon task; retain files/logs
```

Existing lid policies remain unchanged. First validate closed-lid unplug, reconnecting power within the grace period, open-lid battery use, and resume from sleep on a ventilated desk.

#### Read-only diagnostics

Download and extract the source, then open PowerShell in the project directory:

```powershell
# Default mode: read-only inspection
.\LidItSleep.ps1

# Inspect the latest 12 power events within one day
.\LidItSleep.ps1 -Days 1 -MaxEvents 12
```

If Windows blocks downloaded scripts, review the source and follow your organization's execution policy. The tool does not modify script execution policy.

#### Configure lid actions

This example selects Sleep for both external power and battery. Preview first, then apply as needed:

```powershell
.\LidItSleep.ps1 -Mode Apply -BatteryAction Sleep -PluggedInAction Sleep -WhatIf
.\LidItSleep.ps1 -Mode Apply -BatteryAction Sleep -PluggedInAction Sleep
```

An alternative selects Hibernate on battery while retaining Sleep on external power:

```powershell
.\LidItSleep.ps1 -Mode Apply -BatteryAction Hibernate -PluggedInAction Sleep -WhatIf
.\LidItSleep.ps1 -Mode Apply -BatteryAction Hibernate -PluggedInAction Sleep
```

If Sleep on external power interrupts external-display use, select `-PluggedInAction DoNothing`. This changes AC lid behavior and may disengage input suppression; consider [Microsoft's input-suppression documentation](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/power-controls-enableinputsuppression).

#### Restore previous settings

Before each actual change, the tool saves the previous lid policy to a unique JSON file in `backups/` and prints its path. Substitute that path for the placeholder below:

```powershell
.\LidItSleep.ps1 -Mode Restore -BackupPath .\backups\lid-policy-YOUR-BACKUP-ID.json -WhatIf
.\LidItSleep.ps1 -Mode Restore -BackupPath .\backups\lid-policy-YOUR-BACKUP-ID.json
```

Manually select the backup's original power plan before restoring. Restore also backs up the current values. If a write fails, the tool attempts rollback and retains the backup. If the requested values already match, no write or backup occurs.

### Parameters

| Parameter | Values | Default | Description |
| --- | --- | --- | --- |
| `-Mode` | `Inspect`, `Apply`, `Restore` | `Inspect` | Inspect, configure or restore |
| `-BatteryAction` | `Sleep`, `Hibernate` | `Sleep` | Battery lid action in Apply mode |
| `-PluggedInAction` | `Sleep`, `DoNothing` | `Sleep` | AC lid action in Apply mode |
| `-BackupPath` | JSON file path | None | Required in Restore mode |
| `-Days` | 1–90 | 7 | Event lookback period |
| `-MaxEvents` | 1–200 | 24 | Maximum number of returned events |
| `-WhatIf` | Switch | Off | Preview configuration or restore without writing settings or backups |

### Event interpretation

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

### Workflow validation

1. On a ventilated desk, close the lid while using an external display and confirm normal operation.
2. Disconnect as usual and check whether this also switches the laptop to battery power.
3. Wait approximately one minute, open the lid and briefly press the power button if needed to check resume behavior.
4. Run the read-only inspection and review power states, event times and resume reasons.

For longer power-consumption analysis, generate a SleepStudy report in an elevated terminal:

```powershell
powercfg /sleepstudy /output sleepstudy.html
```

Reports may contain device, application and activity information; review and redact them before sharing. Allow an unusually hot device to cool before further testing in a ventilated location.

### Scope

`LidItSleep.ps1` changes only the active power plan's two lid-action values. It does not configure power buttons, timeouts, networking, wake devices, BIOS or security settings. The separately installed guard adds background monitoring and explicit sleep requests.

The guard observes lid and power state, not specific Thunderbolt/USB-C ports or display connection state. Stored lid policies alone cannot guarantee sleep after unplugging with an already closed lid; the guard adds a separate sleep request, never S4. Actual unplug/resume behavior still requires device-specific validation. Organization policy or vendor utilities may override settings or prevent requests.

### Testing and validation

```powershell
.\Test-LidItSleep.ps1
.\Test-Guard.ps1
.\Build-Guard.ps1
# Observe real sensors without requesting sleep; exit after 60 seconds
.\build\LidItSleep.Guard.exe --observe --seconds 60 --state-dir .\test-output
```

The original 20 tests use synthetic events and mocked power interfaces. Another 30 guard tests cover unplugging, cancellation, unknown sensors, resume, retries and duplicate suppression. Neither suite changes real power settings or requests real sleep or hibernation.

| Validation | Current result |
| --- | --- |
| PowerShell 7 tests | Original 20 and guard 30 passed |
| Windows PowerShell 5.1 | Syntax checks passed; local execution policy blocked runtime testing |
| Live inspection | Verified on one Windows 11 25H2 device |
| Configuration writes and restore | Mocked tests passed; real writes have not been verified |
| Hardware sleep behavior | One approximately 39-minute modern standby observation resumed on lid opening with about 0.44 percentage points of battery loss |

The observed device had `Sleep` stored for both AC and battery lid actions. One observation is not a universal compatibility or repair guarantee and does not establish that a particular configuration caused an improvement. Original personal logs are not included.

### Contributing and license

Redacted reproduction steps and code improvements are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting.

Licensed under the [MIT License](LICENSE).

### References

- [Lid action values](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/power-button-and-lid-settings-lid-switch-close-action)
- [Input suppression and closed-lid unplug behavior](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/power-controls-enableinputsuppression)
- [Modern standby wake sources and drain protection](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/modern-standby-wake-sources)
- [SleepStudy](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/modern-standby-sleepstudy)
- [powercfg commands](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options)

[简体中文 ↑](#简体中文) · [English ↑](#english)
