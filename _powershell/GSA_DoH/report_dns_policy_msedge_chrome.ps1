#requires -Version 5.1
<#
.SYNOPSIS
    Report the Edge/Chrome BuiltInDnsClientEnabled policy state.

.DESCRIPTION
    Read-only. No admin required. Shows the current value of the
    BuiltInDnsClientEnabled machine policy for both Microsoft Edge and Google
    Chrome, and interprets what it means (async DNS resolver enabled or
    disabled).

    Context: Chromium's built-in async DNS resolver bypasses the Windows stub
    resolver and sends DNS queries (including TCP:53 for HTTPS/SVCB record
    types) directly to the local DNS server. GSA's driver currently rewrites
    UDP:53 answers only, so TCP:53 answers reach the browser as real public
    IPs and cause bypass leaks.

    The switch to disable this is admin-policy only; there is no user-visible
    UI toggle and no chrome://flags entry in current Edge/Chrome. Set the
    BuiltInDnsClientEnabled DWORD to 0 to force the browser to use the
    Windows stub resolver.

    Companion script: disable_dns_policy_msedge_chrome.ps1

.EXAMPLE
    .\report-msedge-dns-registry.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$targets = @(
    @{ Browser = 'Edge';   Vendor = 'Microsoft' }
    @{ Browser = 'Chrome'; Vendor = 'Google'    }
)

$rows = foreach ($t in $targets) {
    $key = "HKLM:\SOFTWARE\Policies\$($t.Vendor)\$($t.Browser)"
    $keyExists = Test-Path $key
    $val = $null
    if ($keyExists) {
        $val = (Get-ItemProperty -Path $key -Name BuiltInDnsClientEnabled -EA SilentlyContinue).BuiltInDnsClientEnabled
    }

    $state = if ($null -eq $val) {
        '<not set> => default = ENABLED (async DNS active, TCP:53 leaks possible)'
    } elseif ($val -eq 0) {
        '0 => DISABLED (async DNS off, browser uses Windows stub - fixed state)'
    } elseif ($val -eq 1) {
        '1 => ENABLED explicitly (async DNS active, TCP:53 leaks possible)'
    } else {
        "$val => unexpected value"
    }

    [pscustomobject]@{
        Browser   = $t.Browser
        Key       = $key
        KeyExists = $keyExists
        Value     = if ($null -eq $val) { '<not set>' } else { $val }
        State     = $state
    }
}

$rows | Format-Table Browser, Key, KeyExists, Value -AutoSize
Write-Host ''
Write-Host 'Interpretation:' -ForegroundColor Cyan
foreach ($r in $rows) {
    Write-Host ("  {0,-7} {1}" -f $r.Browser, $r.State)
}

Write-Host ''
Write-Host 'To FIX (force stub resolver -> stops TCP:53 leaks):' -ForegroundColor Yellow
Write-Host '  .\fix-msedge-dns-registry.ps1                (requires elevation)'
Write-Host ''
Write-Host 'To VERIFY at runtime, in the browser address bar:' -ForegroundColor Cyan
Write-Host '  edge://policy    -> BuiltInDnsClientEnabled = false, Applied'
Write-Host '  edge://net-internals/#dns -> "Async DNS: disabled"'
