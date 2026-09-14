#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param([ValidateSet('Install','Status','Uninstall')][string]$Mode = 'Install', [ValidateRange(5,120)][int]$DelaySeconds = 10)
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$taskName = 'LidItSleep-Guard-' + $identity.User.Value
$installDirectory = Join-Path $env:LOCALAPPDATA 'LidItSleep'
$exe = Join-Path $installDirectory 'LidItSleep.Guard.exe'
function Resolve-PhysicalFilePath([string]$Path) {
    # Packaged terminals may redirect LocalAppData. Task Scheduler does not share that view.
    if (-not (Test-Path -LiteralPath $Path)) { return $Path }
    if (-not ('LidItSleep.InstallPath' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
namespace LidItSleep {
    public static class InstallPath {
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        public static extern uint GetFinalPathNameByHandle(IntPtr file, StringBuilder path, uint length, uint flags);
    }
}
'@
    }
    $file = [IO.File]::OpenRead($Path)
    try {
        $buffer = New-Object Text.StringBuilder 32768
        $length = [LidItSleep.InstallPath]::GetFinalPathNameByHandle($file.SafeFileHandle.DangerousGetHandle(), $buffer, 32768, 0)
        if ($length -eq 0 -or $length -ge 32768) { throw 'Cannot resolve installed executable path.' }
        $result = $buffer.ToString()
        if ($result.StartsWith('\\?\UNC\')) { return '\\' + $result.Substring(8) }
        if ($result.StartsWith('\\?\')) { return $result.Substring(4) }
        return $result
    } finally { $file.Dispose() }
}
if ($Mode -eq 'Status') {
    Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue | Format-List TaskName,State
    Get-Content -LiteralPath (Join-Path $installDirectory 'state\status.txt') -ErrorAction SilentlyContinue
    Get-Content -LiteralPath (Join-Path $installDirectory 'state\guard.log') -Tail 12 -ErrorAction SilentlyContinue
    return
}
if (-not $PSCmdlet.ShouldProcess($installDirectory, "$Mode per-user lid/battery sleep guard and logon task")) { return }
if ($Mode -eq 'Install') {
    $built = & (Join-Path $PSScriptRoot 'Build-Guard.ps1')
    $accessCheck = Start-Process -FilePath $built -ArgumentList '--check-sleep-access' -WindowStyle Hidden -PassThru -Wait
    if ($accessCheck.ExitCode -ne 0) { throw 'Sleep request privilege is unavailable. Guard was not installed.' }
}
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) { Stop-ScheduledTask -TaskName $taskName }
# Stop only our installed executable, never processes selected by a broad name match.
$physicalExe = Resolve-PhysicalFilePath $exe
Get-Process -Name 'LidItSleep.Guard' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe -or $_.Path -eq $physicalExe } | Stop-Process
if ($Mode -eq 'Uninstall') {
    if ($existing) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false }
    Write-Host "Guard stopped and logon task removed. Files/logs retained at $installDirectory. Power settings unchanged."
    return
}
$null = New-Item -ItemType Directory -Path $installDirectory -Force
Copy-Item -LiteralPath $built -Destination $exe -Force
$physicalExe = Resolve-PhysicalFilePath $exe
$physicalDirectory = Split-Path $physicalExe
$physicalState = Join-Path $physicalDirectory 'state'
$action = New-ScheduledTaskAction -Execute $physicalExe -Argument "--delay $DelaySeconds --state-dir `"$physicalState`"" -WorkingDirectory $physicalDirectory
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $identity.Name
$principal = New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
$null = Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "LidItSleep: request Sleep after $DelaySeconds seconds of confirmed closed lid and battery power; no hibernation fallback." -Force
Start-ScheduledTask -TaskName $taskName
$started = $false
for ($attempt = 0; $attempt -lt 10; $attempt++) {
    Start-Sleep -Milliseconds 500
    $running = @(Get-Process -Name 'LidItSleep.Guard' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $physicalExe -or $_.Path -eq $exe })
    if ($running.Count -gt 0 -and (Get-ScheduledTask -TaskName $taskName).State -eq 'Running') { $started = $true; break }
}
if (-not $started) {
    $result = (Get-ScheduledTaskInfo -TaskName $taskName).LastTaskResult
    throw "Guard did not stay running. Task result=$result. Inspect $physicalState\guard.log."
}
Write-Host "Installed and running: $physicalExe; task=$taskName; delay=$DelaySeconds seconds. Runs as current user, not SYSTEM."
Write-Host 'Existing Windows lid/power settings were not changed. Check -Mode Status for live lid detection.'
