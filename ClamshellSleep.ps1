#Requires -Version 5.1
<#
.SYNOPSIS
Inspect Windows clamshell sleep, or explicitly apply/restore lid policy.
.EXAMPLE
.\ClamshellSleep.ps1
.EXAMPLE
.\ClamshellSleep.ps1 -Mode Apply -BatteryAction Sleep -PluggedInAction Sleep -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('Inspect', 'Apply', 'Restore')][string]$Mode = 'Inspect',
    [ValidateSet('Sleep', 'Hibernate')][string]$BatteryAction = 'Sleep',
    [ValidateSet('Sleep', 'DoNothing')][string]$PluggedInAction = 'Sleep',
    [string]$BackupPath,
    [ValidateRange(1, 90)][int]$Days = 7,
    [ValidateRange(1, 200)][int]$MaxEvents = 24
)

function Initialize-PowerApi {
    if ('ClamshellSleep.Native' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace ClamshellSleep {
    public static class Native {
        [DllImport("powrprof.dll")]
        public static extern uint PowerGetActiveScheme(IntPtr root, out IntPtr scheme);
        [DllImport("kernel32.dll")]
        public static extern IntPtr LocalFree(IntPtr memory);
        [DllImport("powrprof.dll")]
        public static extern uint PowerReadACValueIndex(IntPtr root, ref Guid scheme, ref Guid group, ref Guid setting, out uint value);
        [DllImport("powrprof.dll")]
        public static extern uint PowerReadDCValueIndex(IntPtr root, ref Guid scheme, ref Guid group, ref Guid setting, out uint value);
        [DllImport("powrprof.dll")]
        [return: MarshalAs(UnmanagedType.U1)]
        public static extern bool IsPwrHibernateAllowed();
    }
}
'@
}

function Get-ActiveSchemeId {
    Initialize-PowerApi
    $pointer = [IntPtr]::Zero
    $code = [ClamshellSleep.Native]::PowerGetActiveScheme([IntPtr]::Zero, [ref]$pointer)
    if ($code -ne 0) { throw "PowerGetActiveScheme failed: $code" }
    try { return [Runtime.InteropServices.Marshal]::PtrToStructure($pointer, [type][guid]).ToString() }
    finally { [void][ClamshellSleep.Native]::LocalFree($pointer) }
}

function Get-LidPolicy {
    param([string]$SchemeId = (Get-ActiveSchemeId))
    Initialize-PowerApi
    $scheme = [guid]$SchemeId
    $group = [guid]'4f971e89-eebd-4455-a8de-9e59040e7347'
    $setting = [guid]'5ca83367-6e45-459f-a27b-476b1d01c936'
    [uint32]$ac = 0
    [uint32]$dc = 0
    $code = [ClamshellSleep.Native]::PowerReadACValueIndex([IntPtr]::Zero, [ref]$scheme, [ref]$group, [ref]$setting, [ref]$ac)
    if ($code -ne 0) { throw "Reading AC lid policy failed: $code" }
    $code = [ClamshellSleep.Native]::PowerReadDCValueIndex([IntPtr]::Zero, [ref]$scheme, [ref]$group, [ref]$setting, [ref]$dc)
    if ($code -ne 0) { throw "Reading DC lid policy failed: $code" }
    [pscustomobject]@{ SchemaVersion = 1; SchemeId = $scheme.ToString(); AC = $ac; DC = $dc }
}

function Assert-LidPolicy {
    param($Policy)
    if ($null -eq $Policy) { throw 'Missing policy.' }
    foreach ($key in @('SchemaVersion', 'SchemeId', 'AC', 'DC')) {
        if ($Policy.PSObject.Properties.Name -notcontains $key) { throw "Missing field: $key" }
    }
    if ($Policy.SchemaVersion -ne 1) { throw 'Unsupported backup schema.' }
    $parsedGuid = [guid]::Empty
    if (-not [guid]::TryParse([string]$Policy.SchemeId, [ref]$parsedGuid)) { throw 'Invalid scheme GUID.' }
    foreach ($key in @('AC', 'DC')) {
        if ([string]$Policy.$key -notmatch '^[0-3]$') { throw "Invalid lid action: $key" }
    }
}

function Invoke-PowerCfg {
    param([string[]]$Arguments)
    $result = & "$env:SystemRoot\System32\powercfg.exe" @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "powercfg failed ($LASTEXITCODE): $($result -join ' ')" }
    $result
}

function Write-LidPolicy {
    param($Policy)
    Assert-LidPolicy $Policy
    if ((Get-ActiveSchemeId) -ne $Policy.SchemeId) { throw 'Active plan changed. No plan will be switched automatically.' }
    $null = Invoke-PowerCfg @('/setacvalueindex', $Policy.SchemeId, 'SUB_BUTTONS', 'LIDACTION', [string]$Policy.AC)
    $null = Invoke-PowerCfg @('/setdcvalueindex', $Policy.SchemeId, 'SUB_BUTTONS', 'LIDACTION', [string]$Policy.DC)
    if ((Get-ActiveSchemeId) -ne $Policy.SchemeId) { throw 'Active plan changed during update.' }
    $null = Invoke-PowerCfg @('/setactive', $Policy.SchemeId)
    $check = Get-LidPolicy $Policy.SchemeId
    if ($check.AC -ne $Policy.AC -or $check.DC -ne $Policy.DC) { throw 'Readback verification failed; policy may be managed by your organization.' }
}

function Set-LidPolicySafely {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param($Policy, [string]$BackupDirectory)
    Assert-LidPolicy $Policy
    $before = Get-LidPolicy
    if ($before.SchemeId -ne $Policy.SchemeId) { throw 'Backup belongs to a different active plan. Select that plan manually first.' }
    if ($before.AC -eq $Policy.AC -and $before.DC -eq $Policy.DC) {
        Write-Host 'Lid policy already matches. Nothing changed.'
        return
    }
    if (-not $PSCmdlet.ShouldProcess($Policy.SchemeId, "Set lid actions: AC=$($Policy.AC), DC=$($Policy.DC); back up existing values")) { return }
    $null = New-Item -ItemType Directory -Path $BackupDirectory -Force -ErrorAction Stop
    $backupFile = Join-Path $BackupDirectory ('lid-policy-' + [guid]::NewGuid().ToString('N') + '.json')
    $before | ConvertTo-Json | Set-Content -LiteralPath $backupFile -Encoding UTF8 -ErrorAction Stop
    Write-Host "Backup: $backupFile"
    try { Write-LidPolicy $Policy }
    catch {
        $originalError = $_
        try {
            Write-LidPolicy $before
            Write-Warning 'Update failed; previous lid settings were restored.'
        }
        catch { Write-Warning "Automatic rollback failed. Restore using the backup after resolving the error: $backupFile" }
        throw $originalError
    }
    Write-Host 'Lid policy saved and read back successfully. Test actual suspend/resume on your hardware.'
}

function Convert-SleepEvent {
    param($Event)
    [xml]$xml = $Event.ToXml()
    $data = @{}
    foreach ($node in $xml.Event.EventData.Data) {
        if ($null -ne $node.Name) { $data[[string]$node.Name] = [string]$node.'#text' }
    }
    $kind = switch ([int]$Event.Id) {
        506 { 'Modern standby session start (not proof of low-power sleep)' }
        507 {
            if ($data['SleepEntered'] -eq 'true') { 'Modern standby session end: sleep confirmed' }
            elseif ($data['SleepEntered'] -eq 'false') { 'Screen-off session end: sleep NOT confirmed' }
            else { 'Modern standby session end: sleep status unavailable' }
        }
        42 { if ($data['TargetState'] -eq '5') { 'Hibernate transition requested (S4)' } else { 'Sleep transition requested' } }
        107 { 'Resume from sleep/hibernate' }
        88 { 'Thermal hibernation event' }
        41 { 'Unexpected restart (cause not established)' }
    }
    if ($Event.Id -in @(506, 507) -and $data['Reason'] -eq '55') {
        $kind += '; standby energy-budget policy event, not an overheating diagnosis'
    }
    $seconds = $null
    if ($data.ContainsKey('SleepDurationInUs')) { $seconds = [math]::Round([double]$data['SleepDurationInUs'] / 1000000, 1) }
    [pscustomobject]@{
        TimeLocal = $Event.TimeCreated
        EventId = $Event.Id
        Interpretation = $kind
        ReasonCode = $data['Reason']
        LidOpen = $data['LidOpenState']
        ExternalMonitor = $data['ExternalMonitorConnectedState']
        SleepSeconds = $seconds
    }
}

function Get-SleepTimeline {
    param([int]$Days = 7, [int]$MaxEvents = 24)
    try {
        Get-WinEvent -FilterHashtable @{
            LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'
            Id = @(42, 107, 506, 507, 88, 41); StartTime = (Get-Date).AddDays(-$Days)
        } -MaxEvents $MaxEvents -ErrorAction Stop | ForEach-Object { Convert-SleepEvent $_ }
    }
    catch {
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { Write-Host 'No matching events in the selected period.' }
        else { throw }
    }
}

# Dot-source to load functions for tests without inspecting or changing the machine.
if ($MyInvocation.InvocationName -eq '.') { return }
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Windows is required.' }
switch ($Mode) {
    'Inspect' {
        Write-Host 'Available sleep states:'
        Invoke-PowerCfg @('/a')
        Write-Host 'Stored lid policy (0=DoNothing, 1=Sleep, 2=Hibernate, 3=Shutdown):'
        Get-LidPolicy | Format-List
        Write-Host 'Recent power events (local time; newest first):'
        Get-SleepTimeline -Days $Days -MaxEvents $MaxEvents | Format-List
    }
    'Apply' {
        $policy = Get-LidPolicy
        $policy.AC = @{ Sleep = 1; DoNothing = 0 }[$PluggedInAction]
        $policy.DC = @{ Sleep = 1; Hibernate = 2 }[$BatteryAction]
        if ($BatteryAction -eq 'Hibernate') {
            Initialize-PowerApi
            if (-not [ClamshellSleep.Native]::IsPwrHibernateAllowed()) { throw 'Hibernation is not available. Inspect powercfg /a and configure it explicitly before retrying.' }
        }
        Set-LidPolicySafely -Policy $policy -BackupDirectory (Join-Path $PSScriptRoot 'backups') -WhatIf:$WhatIfPreference
    }
    'Restore' {
        if (-not $BackupPath) { throw 'Restore requires -BackupPath.' }
        $policy = Get-Content -LiteralPath $BackupPath -Raw -ErrorAction Stop | ConvertFrom-Json
        Set-LidPolicySafely -Policy $policy -BackupDirectory (Join-Path $PSScriptRoot 'backups') -WhatIf:$WhatIfPreference
    }
}
