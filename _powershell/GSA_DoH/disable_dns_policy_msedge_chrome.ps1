#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
    Disable the Edge/Chrome built-in async DNS resolver via machine policy.

.DESCRIPTION
    Writes BuiltInDnsClientEnabled = 0 (DWORD) under
    HKLM\SOFTWARE\Policies\Microsoft\Edge and HKLM\SOFTWARE\Policies\Google\Chrome,
    then optionally flushes DNS caches and kills the browsers so the new
    policy takes effect immediately.

    See report_dns_policy_msedge_chrome.ps1 for a read-only view of the current
    state and rationale.

    -Revert removes the values instead of writing them (returns to default =
    async DNS enabled).

    -SkipFlush suppresses the DNS-cache flush + browser-kill step (default
    is to do them).

.EXAMPLE
    # Standard use: push the policy + flush + kill browsers.
    .\disable_dns_policy_msedge_chrome.ps1

.EXAMPLE
    # Just push the policy; leave browsers alone.
    .\disable_dns_policy_msedge_chrome.ps1 -SkipFlush

.EXAMPLE
    # Undo the policy (delete the values).
    .\disable_dns_policy_msedge_chrome.ps1 -Revert
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [switch]$Revert,
    [switch]$SkipFlush
)

$ErrorActionPreference = 'Stop'

$targets = @(
    @{ Browser = 'Edge';   Vendor = 'Microsoft' }
    @{ Browser = 'Chrome'; Vendor = 'Google'    }
)

function Show-CurrentState {
    param($Where)
    Write-Host ""
    Write-Host "[$Where] Current BuiltInDnsClientEnabled state:" -ForegroundColor Cyan
    foreach ($t in $targets) {
        $key = "HKLM:\SOFTWARE\Policies\$($t.Vendor)\$($t.Browser)"
        $val = if (Test-Path $key) {
            (Get-ItemProperty -Path $key -Name BuiltInDnsClientEnabled -EA SilentlyContinue).BuiltInDnsClientEnabled
        } else { $null }
        $shown = if ($null -eq $val) { '<not set>' } else { "$val" }
        Write-Host ("  {0,-7} {1} = {2}" -f $t.Browser, $key, $shown)
    }
}

Show-CurrentState -Where 'BEFORE'

if ($Revert) {
    Write-Host ""
    Write-Host "Reverting: removing BuiltInDnsClientEnabled from Edge + Chrome policy keys..." -ForegroundColor Yellow
    foreach ($t in $targets) {
        $key = "HKLM:\SOFTWARE\Policies\$($t.Vendor)\$($t.Browser)"
        if (Test-Path $key) {
            if ($PSCmdlet.ShouldProcess("$key\BuiltInDnsClientEnabled", 'Remove value')) {
                Remove-ItemProperty -Path $key -Name BuiltInDnsClientEnabled -EA SilentlyContinue
                Write-Host "  removed: $key\BuiltInDnsClientEnabled" -ForegroundColor Green
            }
        } else {
            Write-Host "  n/a:     $key (key does not exist)" -ForegroundColor DarkGray
        }
    }
} else {
    Write-Host ""
    Write-Host "Applying: BuiltInDnsClientEnabled = 0 to Edge + Chrome policy keys..." -ForegroundColor Yellow
    foreach ($t in $targets) {
        $key = "HKLM:\SOFTWARE\Policies\$($t.Vendor)\$($t.Browser)"
        if ($PSCmdlet.ShouldProcess("$key\BuiltInDnsClientEnabled", 'Set to 0 (DWORD)')) {
            New-Item -Path $key -Force | Out-Null
            New-ItemProperty -Path $key -Name BuiltInDnsClientEnabled -PropertyType DWord -Value 0 -Force | Out-Null
            Write-Host "  set:     $key\BuiltInDnsClientEnabled = 0" -ForegroundColor Green
        }
    }
}

Show-CurrentState -Where 'AFTER'

if (-not $SkipFlush) {
    Write-Host ""
    Write-Host "Flushing Windows DNS cache..." -ForegroundColor Yellow
    Clear-DnsClientCache
    Write-Host "  Windows DNS cache cleared." -ForegroundColor Green

    Write-Host ""
    Write-Host "Killing Edge + Chrome so their in-process DNS caches drop..." -ForegroundColor Yellow
    $procs = Get-Process msedge, msedgewebview2, chrome -EA SilentlyContinue
    if ($procs) {
        $procs | Stop-Process -Force -EA SilentlyContinue
        Start-Sleep -Milliseconds 500
        Write-Host ("  killed {0} browser process(es)." -f $procs.Count) -ForegroundColor Green
    } else {
        Write-Host "  no browser processes were running." -ForegroundColor DarkGray
    }
} else {
    Write-Host ""
    Write-Host "-SkipFlush set: NOT flushing DNS cache and NOT killing browsers." -ForegroundColor DarkGray
    Write-Host "  Policy will not take effect until each browser is fully restarted." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "Verify (in each browser after relaunch):" -ForegroundColor Cyan
Write-Host "  edge://policy                -> BuiltInDnsClientEnabled = false, Applied"
Write-Host "  edge://net-internals/#dns    -> 'Async DNS: disabled'"
Write-Host "  chrome://policy              -> same"
Write-Host "  chrome://net-internals/#dns  -> same"
Write-Host ""
Write-Host "Runtime signal (no more TCP:53 out of msedge/chrome):" -ForegroundColor Cyan
Write-Host "  Get-NetTCPConnection -RemotePort 53 -EA SilentlyContinue |"
Write-Host "      ForEach-Object { \$p = Get-Process -Id \$_.OwningProcess -EA 0"
Write-Host "                        [pscustomobject]@{ Proc=\$p.Name; PID=\$_.OwningProcess; Remote=\$_.RemoteAddress } }"
