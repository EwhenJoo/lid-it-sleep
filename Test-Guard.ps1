#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Add-Type -Path (Join-Path $PSScriptRoot 'GuardPolicy.cs')
Add-Type -Path (Join-Path $PSScriptRoot 'SleepRequest.cs')
$count = 0
function Check($Condition, $Label) {
    if (-not $Condition) { throw "FAIL: $Label" }
    $script:count++
    Write-Host "PASS: $Label"
}
function New-Policy { New-Object LidItSleep.GuardPolicy 10 }
$g = New-Policy
Check (-not $g.Observe($true,$true,0)) 'Docked closed lid does not sleep'
Check (-not $g.Observe($false,$true,1)) 'Unplug starts grace period'
Check (-not $g.Observe($false,$true,10)) 'Does not trigger before full delay'
Check ($g.Observe($false,$true,11)) 'Closed-lid unplug requests sleep at deadline'
Check (-not $g.Observe($false,$true,100)) 'No duplicate request or resume loop'
Check ($g.Attempts -eq 1) 'Exactly one attempt in unchanged interval'
$null = $g.Observe($true,$true,101)
$null = $g.Observe($false,$true,102)
Check ($g.Observe($false,$true,112)) 'Replug rearms for next unplug'
$g = New-Policy
$null = $g.Observe($false,$true,0)
Check (-not $g.Observe($false,$false,9)) 'Opening lid cancels request'
Check (-not $g.Observe($false,$true,10)) 'Reclosing starts a fresh delay'
Check ($g.Observe($false,$true,20)) 'Closing lid on battery is also protected'
$g = New-Policy
$null = $g.Observe($false,$true,0)
$null = $g.Observe($true,$true,9)
Check (-not $g.Observe($false,$true,10)) 'Brief power disconnect/reconnect cancels countdown'
Check ($g.Observe($false,$true,20)) 'Stable second disconnect works'
$g = New-Policy
Check (-not $g.Observe($false,$null,0)) 'Unknown lid never authorizes sleep'
Check (-not $g.Observe($null,$true,20)) 'Unknown supply never authorizes sleep'
$null = $g.Observe($false,$true,21)
$null = $g.Observe($null,$true,29)
Check (-not $g.Observe($false,$true,31)) 'Unknown state resets grace period'
Check ($g.Observe($false,$true,41)) 'Recovered sensors require full fresh delay'
$g = New-Policy
$null = $g.Observe($false,$true,0)
$g.Invalidate()
Check (-not $g.Observe($false,$true,500)) 'Resume or message-loop stall discards stale deadline'
Check ($g.Observe($false,$true,510)) 'Fresh post-resume countdown can complete'
$g.Invalidate()
Check (-not $g.Observe($false,$true,1000)) 'Invalidating observation does not clear successful latch'
$g = New-Policy
$null = $g.Observe($false,$true,0)
$null = $g.Observe($false,$true,10)
$g.RequestFailed(10)
Check (-not $g.Observe($false,$true,69)) 'Failed request has a 60-second backoff'
$null = $g.Observe($false,$true,70)
Check ($g.Observe($false,$true,80)) 'Failed request is retried only after fresh delay'
$g.RequestFailed(80)
$null = $g.Observe($false,$true,140)
$null = $g.Observe($false,$true,150)
$g.RequestFailed(150)
Check (-not $g.Observe($false,$true,10000)) 'Retries bounded to three per interval'
$null = $g.Observe($false,$false,10001)
$null = $g.Observe($false,$true,10002)
Check ($g.Observe($false,$true,10012)) 'User reopening lid rearms after repeated failures'
$g = New-Policy
$null = $g.Observe($false,$true,0)
Check ($g.Observe($false,$true,10)) 'Starting/restarting already closed on battery is covered'
$g.CancelDispatch()
Check ($g.Attempts -eq 0 -and -not $g.Latched) 'Last-moment sensor change cancels dispatch without consuming attempt'
$null = $g.Observe($null,$true,11)
$null = $g.Observe($false,$true,12)
Check ($g.Observe($false,$true,22)) 'Cancelled dispatch can retry after fresh valid observations'
$script:apiCalls = 0
$script:apiArguments = @()
$fakeApi = [LidItSleep.SleepRequest+SuspendApi] {
    param($hibernate,$force,$disableWake)
    $script:apiCalls++
    $script:apiArguments = @($hibernate,$force,$disableWake)
    return $true
}
$accepted = [LidItSleep.SleepRequest]::Invoke($fakeApi)
Check (-not $script:apiArguments[0] -and -not $script:apiArguments[1] -and -not $script:apiArguments[2]) 'Sleep API explicitly disables hibernation and preserves wake events'
Check ($accepted -and $script:apiCalls -eq 1) 'Sleep request invokes the API exactly once'
$script:apiCalls = 0
$failureApi = [LidItSleep.SleepRequest+SuspendApi] { param($h,$f,$w); $script:apiCalls++; return $false }
Check (-not [LidItSleep.SleepRequest]::Invoke($failureApi) -and $script:apiCalls -eq 1) 'API rejection propagates without fallback to hibernation'
$errorApi = [LidItSleep.SleepRequest+SuspendApi] { param($h,$f,$w); throw 'Simulated power API error' }
$thrown = $false
try { [void][LidItSleep.SleepRequest]::Invoke($errorApi) } catch { $thrown = $true }
Check $thrown 'Power API exceptions propagate for bounded retry'
Write-Host "All $count guard tests passed. No sleep or hibernation requested."
