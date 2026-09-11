# lid-it-sleep

**Windows 合盖电源策略配置与睡眠诊断工具。**

简体中文 | [English](README.en.md) · [MIT License](LICENSE)

`lid-it-sleep` 面向合盖使用外接显示器、断开连接后携带笔记本的场景，提供电源策略检查、合盖动作配置和睡眠事件分析。通过区分配置值、熄屏会话与实际睡眠记录，帮助用户验证设备是否按预期进入睡眠或休眠。

## 功能

- **只读检查**：查看可用睡眠状态、活动电源方案的合盖策略及近期电源事件。
- **策略配置**：分别设置电池和外接电源供电时的合盖动作。
- **可恢复修改**：支持 `-WhatIf` 预览、修改前备份、写入后校验和失败回滚。
- **事件分析**：区分熄屏、现代待机、休眠请求、热保护和异常重启。
- **本地运行**：无需服务或常驻进程，不包含遥测或联网功能。

## 环境要求

| 项目 | 要求或验证状态 |
| --- | --- |
| 操作系统 | Windows；已在 Windows 11 25H2 上验证只读功能 |
| PowerShell 7 | 7.6.5 已通过运行验证和 20 项模拟测试 |
| Windows PowerShell 5.1 | 已通过语法检查，尚未完成运行验证 |
| 修改权限 | 取决于系统权限与组织策略；写入可能需要管理员终端 |
| 休眠配置 | 选择 `Hibernate` 前，系统必须已支持并启用休眠 |

睡眠类型由设备固件和 Windows 决定。现代待机使用 S0 低功耗空闲，休眠使用 S4。工具不会将 S0 转换为传统 S3 睡眠。

## 快速开始

下载并解压源码，在项目目录打开 PowerShell：

```powershell
# 默认模式：只读检查
.\ClamshellSleep.ps1

# 查看最近一天的 12 条电源事件
.\ClamshellSleep.ps1 -Days 1 -MaxEvents 12
```

若系统阻止执行下载的脚本，请先审阅源码，并遵循所在组织的执行策略。工具不会更改脚本执行策略。

### 配置合盖动作

以下示例将接电和电池供电时的合盖动作都设为睡眠。先预览，再按需应用：

```powershell
.\ClamshellSleep.ps1 -Mode Apply -BatteryAction Sleep -PluggedInAction Sleep -WhatIf
.\ClamshellSleep.ps1 -Mode Apply -BatteryAction Sleep -PluggedInAction Sleep
```

可选配置：使用电池时合盖进入休眠，接电时保留睡眠动作。

```powershell
.\ClamshellSleep.ps1 -Mode Apply -BatteryAction Hibernate -PluggedInAction Sleep -WhatIf
.\ClamshellSleep.ps1 -Mode Apply -BatteryAction Hibernate -PluggedInAction Sleep
```

如果接电合盖设为睡眠会中断外接显示器的使用，可选择 `-PluggedInAction DoNothing`。该选项会改变接电合盖行为，并可能使输入抑制不再生效；请结合[微软关于输入抑制的说明](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/power-controls-enableinputsuppression)评估。

### 恢复原设置

每次实际修改前，工具会将原合盖策略保存为 `backups/` 中的唯一 JSON 文件，并打印路径。用实际路径替换下面的占位文件名：

```powershell
.\ClamshellSleep.ps1 -Mode Restore -BackupPath .\backups\lid-policy-YOUR-BACKUP-ID.json -WhatIf
.\ClamshellSleep.ps1 -Mode Restore -BackupPath .\backups\lid-policy-YOUR-BACKUP-ID.json
```

恢复前需手动选中备份对应的电源方案。恢复操作也会备份当前值；若写入失败，工具会尝试回滚并保留备份。若目标配置与当前值一致，则不写入也不生成备份。

## 参数

| 参数 | 可选值 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `-Mode` | `Inspect`、`Apply`、`Restore` | `Inspect` | 检查、配置或恢复 |
| `-BatteryAction` | `Sleep`、`Hibernate` | `Sleep` | Apply 模式下的电池合盖动作 |
| `-PluggedInAction` | `Sleep`、`DoNothing` | `Sleep` | Apply 模式下的接电合盖动作 |
| `-BackupPath` | JSON 文件路径 | 无 | Restore 模式必填 |
| `-Days` | 1–90 | 7 | 检查事件的时间范围 |
| `-MaxEvents` | 1–200 | 24 | 返回的最大事件数 |
| `-WhatIf` | 开关 | 关闭 | 预览配置或恢复，不写入设置或备份 |

## 事件解读

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

## 工作流验证

1. 在通风桌面上，合盖连接外接显示器，确认工作状态正常。
2. 按日常流程断开连接，并确认是否同时切换到电池供电。
3. 等待约一分钟后开盖，必要时短按电源键，检查能否正常恢复。
4. 运行只读检查，核对进入的电源状态、事件时间和恢复原因。

如需分析长时间待机功耗，可在管理员终端生成 SleepStudy 报告：

```powershell
powercfg /sleepstudy /output sleepstudy.html
```

报告可能包含设备、应用和活动时间信息，分享前请审阅并脱敏。明显发热的设备应先散热，再在通风条件下测试。

## 适用范围

工具仅修改活动电源方案的两项合盖动作，不调整电源按键、超时、网络、唤醒设备、BIOS 或安全设置。

它不监听雷电或 USB-C 拔线事件。Windows 文档描述了部分合盖拔电源场景下对电池合盖策略的重新评估，但实际结果取决于硬件、驱动、供电状态和系统策略。已合盖后拔线是否触发预期的睡眠或休眠，需要在目标设备上验证。组织策略或厂商软件也可能覆盖已保存的设置。

## 测试与验证

```powershell
.\Test-ClamshellSleep.ps1
```

20 项自动化测试使用虚构事件和模拟电源接口，覆盖事件解释、校验、预览、备份、恢复、重复应用及失败回滚，不修改真实电源设置。

| 验证项目 | 当前结果 |
| --- | --- |
| PowerShell 7 测试 | 20 项通过 |
| Windows PowerShell 5.1 | 语法检查通过；本机执行策略阻止运行，运行兼容性尚待验证 |
| 实时读取 | 在一台 Windows 11 25H2 设备上通过 |
| 配置写入与恢复 | 已通过模拟测试，尚未进行真实写入验证 |
| 硬件睡眠行为 | 一次约 39 分钟的现代待机观察正常开盖恢复，电量下降约 0.44 个百分点 |

该观察时读取到的接电和电池合盖动作均为 `Sleep`。单次观察不构成通用兼容性或故障修复保证，也不能证明行为改善由特定配置引起。仓库不包含原始个人日志。

## 贡献与许可

欢迎提交经过脱敏的复现步骤和代码改进。提交前请阅读[贡献说明](CONTRIBUTING.md)。

本项目采用 [MIT License](LICENSE)。

## 参考资料

- [合盖动作的取值](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/power-button-and-lid-settings-lid-switch-close-action)
- [输入抑制与合盖拔电源行为](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/power-controls-enableinputsuppression)
- [现代待机唤醒与耗电保护](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/modern-standby-wake-sources)
- [SleepStudy](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/modern-standby-sleepstudy)
- [powercfg 命令](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options)
