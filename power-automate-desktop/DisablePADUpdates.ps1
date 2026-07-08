#Requires -Version 5.1
<#
.SYNOPSIS
    Disables Power Automate Desktop (PAD) update notifications on a runner machine.

.DESCRIPTION
    When a new version of PAD is available, PAD shows a modal update dialog on
    startup that blocks the flow runner from loading — causing C TWO PAD runs to
    fail with "Flow did not start - no runner process was detected".

    This script permanently suppresses the update check by setting DisableUpdate=1
    in two registry locations:
      * HKLM:\SOFTWARE\Policies\Microsoft\Power Automate Desktop  (policy key,
        highest precedence, survives PAD self-updates)
      * HKLM:\SOFTWARE\Microsoft\Power Automate Desktop           (app key, fallback)

    Run ONCE per runner machine, elevated (Run as administrator). Restart PAD
    afterwards and confirm the update dialog no longer appears on launch. When you
    want to update PAD, do it manually outside scheduled C TWO execution windows.

.NOTES
    C TWO Automate AS · customersuccess@ctwo.com
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

# Require elevation - writing to HKLM needs administrator rights
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "This script must be run as administrator (it writes to HKLM)." -ForegroundColor Red
    exit 1
}

$policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Power Automate Desktop"
$appPath    = "HKLM:\SOFTWARE\Microsoft\Power Automate Desktop"

# Policy path takes precedence and survives PAD updates
if (-not (Test-Path $policyPath)) { New-Item -Path $policyPath -Force | Out-Null }
Set-ItemProperty -Path $policyPath -Name "DisableUpdate" -Value 1 -Type DWord

# Also set on the app key as a fallback
if (-not (Test-Path $appPath)) { New-Item -Path $appPath -Force | Out-Null }
Set-ItemProperty -Path $appPath -Name "DisableUpdate" -Value 1 -Type DWord

Write-Host "PAD update notifications disabled (policy + app keys)." -ForegroundColor Green
Write-Host "Restart Power Automate Desktop and confirm the update dialog no longer appears." -ForegroundColor Green
