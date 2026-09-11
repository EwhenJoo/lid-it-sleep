#Requires -Version 5.1
# Standalone tests: no Pester dependency, no native calls or real power writes.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ClamshellSleep.ps1')
$script:passed = 0
function Assert-True($Condition, [string]$Label) {
    if (-not $Condition) { throw "FAIL: $Label" }
    $script:passed++
    Write-Host "PASS: $Label"
}
function Assert-Throws([scriptblock]$Action, [string]$Label) {
    $thrown = $false
    try { & $Action } catch { $thrown = $true }
    Assert-True $thrown $Label
}
function New-TestEvent([int]$Id, [string]$Data) {
    $event = [pscustomobject]@{ Id = $Id; TimeCreated = [datetime]'2000-01-01T12:00:00'; Xml = "<Event><EventData>$Data</EventData></Event>" }
    $event | Add-Member -MemberType ScriptMethod -Name ToXml -Value { $this.Xml }
    $event
}

$event = Convert-SleepEvent (New-TestEvent 507 '<Data Name="SleepEntered">false</Data><Data Name="SleepDurationInUs">0</Data>')
Assert-True ($event.Interpretation -like '*sleep NOT confirmed*') 'Screen-off must not be reported as sleep'
$event = Convert-SleepEvent (New-TestEvent 507 '<Data Name="SleepEntered">true</Data><Data Name="SleepDurationInUs">120000000</Data>')
Assert-True ($event.Interpretation -like '*sleep confirmed*' -and $event.SleepSeconds -eq 120) 'Confirmed sleep and microsecond conversion'
$event = Convert-SleepEvent (New-TestEvent 507 '<Data Name="Reason">15</Data>')
Assert-True ($event.Interpretation -like '*unavailable*' -and $null -eq $event.SleepSeconds) 'Missing fields remain unknown'
$event = Convert-SleepEvent (New-TestEvent 42 '<Data Name="TargetState">5</Data>')
Assert-True ($event.Interpretation -eq 'Hibernate transition requested (S4)') 'Windows power-state enum 5 maps to S4'
$event = Convert-SleepEvent (New-TestEvent 506 '<Data Name="Reason">55</Data>')
Assert-True ($event.Interpretation -like '*not an overheating diagnosis*') 'Energy-budget event is not an overheating diagnosis'
$event = Convert-SleepEvent (New-TestEvent 88 '<Data Name="Reason">1</Data>')
Assert-True ($event.Interpretation -eq 'Thermal hibernation event') 'Thermal event remains distinct'

$script:fakeScheme = '11111111-1111-1111-1111-111111111111'
$script:fakeAC = 0
$script:fakeDC = 1
$script:calls = @()
$script:failNextDC = $false
function Get-ActiveSchemeId { $script:fakeScheme }
function Get-LidPolicy {
    param([string]$SchemeId = $script:fakeScheme)
    [pscustomobject]@{ SchemaVersion = 1; SchemeId = $SchemeId; AC = $script:fakeAC; DC = $script:fakeDC }
}
function Invoke-PowerCfg {
    param([string[]]$Arguments)
    $script:calls += ,$Arguments
    switch ($Arguments[0]) {
        '/setacvalueindex' { $script:fakeAC = [int]$Arguments[4] }
        '/setdcvalueindex' {
            if ($script:failNextDC) { $script:failNextDC = $false; throw 'Simulated write failure' }
            $script:fakeDC = [int]$Arguments[4]
        }
        '/setactive' { if ($Arguments[1] -ne $script:fakeScheme) { throw 'Unexpected scheme activation' } }
        default { throw "Unexpected command: $($Arguments[0])" }
    }
}
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('clamshell-tests-' + [guid]::NewGuid().ToString('N'))
try {
    $target = [pscustomobject]@{ SchemaVersion = 1; SchemeId = $script:fakeScheme; AC = 1; DC = 2 }
    Set-LidPolicySafely -Policy $target -BackupDirectory $testRoot -WhatIf
    Assert-True ($script:calls.Count -eq 0 -and -not (Test-Path -LiteralPath $testRoot)) 'WhatIf makes no writes or backups'
    Set-LidPolicySafely -Policy $target -BackupDirectory $testRoot
    Assert-True ($script:fakeAC -eq 1 -and $script:fakeDC -eq 2) 'Apply writes requested lid values'
    $files = @(Get-ChildItem -LiteralPath $testRoot -Filter '*.json')
    $original = Get-Content -LiteralPath $files[0].FullName -Raw | ConvertFrom-Json
    Assert-True ($files.Count -eq 1 -and $original.AC -eq 0 -and $original.DC -eq 1) 'Backup contains original values'
    $count = $script:calls.Count
    Set-LidPolicySafely -Policy $target -BackupDirectory $testRoot
    Assert-True ($script:calls.Count -eq $count -and @(Get-ChildItem -LiteralPath $testRoot).Count -eq 1) 'Idempotent apply does not write'
    Set-LidPolicySafely -Policy $original -BackupDirectory $testRoot
    Assert-True ($script:fakeAC -eq 0 -and $script:fakeDC -eq 1) 'Restore returns original values'
    Assert-True (@(Get-ChildItem -LiteralPath $testRoot).Count -eq 2) 'Restore also creates a recovery backup'
    $script:failNextDC = $true
    Assert-Throws { Set-LidPolicySafely -Policy $target -BackupDirectory $testRoot } 'Partial write surfaces the original failure'
    Assert-True ($script:fakeAC -eq 0 -and $script:fakeDC -eq 1) 'Partial write rolls back both lid values'
    $count = $script:calls.Count
    $wrong = [pscustomobject]@{ SchemaVersion = 1; SchemeId = '22222222-2222-2222-2222-222222222222'; AC = 1; DC = 1 }
    Assert-Throws { Set-LidPolicySafely -Policy $wrong -BackupDirectory $testRoot } 'Reject backup for another active plan'
    Assert-True ($script:calls.Count -eq $count) 'Plan mismatch does not write'
    Assert-Throws { Assert-LidPolicy ([pscustomobject]@{ SchemaVersion = 1; SchemeId = $script:fakeScheme; AC = 9; DC = 1 }) } 'Reject invalid action index'
    Assert-Throws { Assert-LidPolicy ([pscustomobject]@{ SchemaVersion = 1; SchemeId = 'bad-guid'; AC = 1; DC = 1 }) } 'Reject malformed GUID'
    Assert-Throws { Assert-LidPolicy ([pscustomobject]@{ SchemaVersion = 2; SchemeId = $script:fakeScheme; AC = 1; DC = 1 }) } 'Reject unsupported schema'
    Assert-Throws { Assert-LidPolicy ([pscustomobject]@{ SchemaVersion = 1; SchemeId = $script:fakeScheme; AC = 1 }) } 'Reject incomplete backup'
    Write-Host "All $script:passed tests passed. No real power settings were changed."
}
finally {
    # Delete only this run's checked, uniquely named temporary directory.
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    if ($resolvedTestRoot.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolvedTestRoot) -match '^clamshell-tests-[a-f0-9]{32}$' -and
        (Test-Path -LiteralPath $resolvedTestRoot)) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
