#Requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory = (Join-Path $PSScriptRoot 'build'))
$ErrorActionPreference = 'Stop'
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
$output = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) 'LidItSleep.Guard.exe'
& $compiler /nologo /target:winexe /optimize+ /reference:System.Windows.Forms.dll "/out:$output" (Join-Path $PSScriptRoot 'GuardPolicy.cs') (Join-Path $PSScriptRoot 'LidItSleep.Guard.cs')
if ($LASTEXITCODE -ne 0) { throw 'Guard compilation failed.' }
Write-Output $output
