# powershell.exe -NoProfile -ExecutionPolicy Bypass -File "Install-WindowsUpdates.ps1"
#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
Interactively updates Windows, WinGet apps, Store apps, and the default Ubuntu WSL distro.
.DESCRIPTION
Run in an elevated PowerShell console as your usual Windows user.
The default WSL distribution must be Ubuntu; sudo may request its password.
WSL executes Bash directly so the default shell cannot expand its commands first.
WinGet respects pins and skips unknown versions. Other Store apps use the Store CLI.
The consumer Store CLI (store.exe, not the msstore developer CLI) must be available.
Store updates use --apply to skip confirmation; CLI output is retained in the log.
Native CLI output is decoded as UTF-8 so progress text and tables remain readable.
The requested WSL command clears Bash history only after every upgrade succeeds.
Version changes and per-update results are summarized; full output is saved in C:\Users\hisriram\WindowsUpdateLogs.
No restart is requested from WinGet or WUA. Restart occurs only after your final approval.
After the restart prompt, history saving is disabled and current-session and saved
PSReadLine history is cleared before any restart command runs. Cleanup failure prevents restart.
PowerShell then exits. Other open PowerShell sessions have independent in-memory history
and may save it again; close them first if you also need their history removed.
The update transcript is retained.
.EXAMPLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-WindowsUpdates.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$results = [System.Collections.Generic.List[object]]::new()
$reboot = $false
$logDirectory = 'C:\Users\hisriram\WindowsUpdateLogs'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$log = Join-Path $logDirectory ("Updates-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$resultNames = @('Not started', 'In progress', 'Succeeded', 'Succeeded with errors', 'Failed', 'Aborted')

function Confirm-Action([string]$Question, [bool]$DefaultYes = $false) {
    $hint = if ($DefaultYes) { '[Y]/N' } else { 'Y/[N]' }
    while ($true) {
        $answer = (Read-Host "$Question ($hint)").Trim()
        if (!$answer) { return $DefaultYes }
        if ($answer -match '^(y|yes)$') { return $true }
        if ($answer -match '^(n|no)$') { return $false }
        Write-Host 'Please enter Y or N.'
    }
}

function Add-Result([string]$Area, [string]$Item, [string]$Status) {
    $results.Add([pscustomobject]@{ Area = $Area; Item = $Item; Result = $Status })
}

function Invoke-Step([string]$Name, [scriptblock]$Action) {
    Write-Host "`n=== $Name ===" -ForegroundColor Cyan
    try {
        & $Action
    } catch {
        Add-Result $Name 'Operation' "Failed: $($_.Exception.Message)"
        Write-Warning "$Name failed: $($_.Exception.Message). Review the log; subsequent stages will still run."
    }
}

function Invoke-Native([string]$File, [string[]]$Arguments) {
    $previousEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
        & $File @Arguments | Out-Host
        $code = $LASTEXITCODE
    } finally {
        [Console]::OutputEncoding = $previousEncoding
    }
    if ($File -eq 'winget.exe' -and ($code -band 0xFFFFFFFFL) -eq 0x8A15002BL) {
        Write-Host 'No applicable upgrades.'
    } elseif ($code -ne 0) {
        throw "$File exited with code $code. Earlier packages may have updated; later chained commands may not have run."
    }
}

function Clear-UpdateHistory {
    $historyOptions = Get-Command 'Get-PSReadLineOption' -ErrorAction SilentlyContinue
    if ($null -ne $historyOptions) {
        $historyPath = (Get-PSReadLineOption).HistorySavePath
        # Disable saving first so neither cleanup nor restart can repopulate the file.
        Set-PSReadLineOption -HistorySaveStyle SaveNothing -ErrorAction Stop
        [Microsoft.PowerShell.PSConsoleReadLine]::ClearHistory()
        if (Test-Path -LiteralPath $historyPath -ErrorAction Stop) {
            Set-Content -LiteralPath $historyPath -Value '' -NoNewline -ErrorAction Stop
        }
    } else {
        Write-Host 'PSReadLine is unavailable; this session has no PSReadLine history to clear.'
    }
    Clear-History -ErrorAction Stop
    Write-Host 'PowerShell command history cleared; history saving is disabled for this session.'
}

function Complete-UpdateSession([bool]$Restart) {
    Clear-UpdateHistory
    if ($Restart) {
        Write-Host 'Restarting Windows...'
        Restart-Computer -ErrorAction Stop
    } else {
        Write-Host 'Restart declined. Restart later if required to complete installation.'
    }
}

function Get-WindowsInventory {
    $inventory = @{}
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($root in $roots) {
        if (Test-Path $root) {
            foreach ($app in (Get-ItemProperty "$root\*")) {
                if ($app.DisplayName -and $app.DisplayVersion) {
                    $inventory["Desktop: $($app.DisplayName)"] = [string]$app.DisplayVersion
                }
            }
        }
    }
    foreach ($app in (Get-AppxPackage)) {
        $inventory["Store: $($app.Name)"] = [string]$app.Version
    }
    return $inventory
}

function Get-UbuntuInventory {
    $lines = & wsl.exe --exec bash -c 'dpkg-query -W'
    if ($LASTEXITCODE -ne 0) { throw 'Unable to read Ubuntu package versions.' }
    $inventory = @{}
    foreach ($line in $lines) {
        $parts = $line -split "`t", 2
        if ($parts.Count -eq 2) { $inventory["Ubuntu: $($parts[0])"] = $parts[1] }
    }
    return $inventory
}

function Show-Changes([string]$Area, [hashtable]$Before, [hashtable]$After) {
    foreach ($name in ($After.Keys | Sort-Object)) {
        if (!$Before.ContainsKey($name)) {
            Add-Result $Area $name "Installed: $($After[$name])"
        } elseif ($Before[$name] -ne $After[$name]) {
            Add-Result $Area $name "$($Before[$name]) -> $($After[$name])"
        }
    }
    foreach ($name in ($Before.Keys | Sort-Object)) {
        if (!$After.ContainsKey($name)) { Add-Result $Area $name 'Removed/replaced' }
    }
}

# WUA requires an IDispatch callback even though progress is polled on this thread.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
[ComVisible(true), Guid("EBA6EF99-A617-46A3-A94E-C9B62D338E32"),
 InterfaceType(ComInterfaceType.InterfaceIsIDispatch)]
public interface IUpdateCompletion {
    [DispId(0)] void Invoke(object job, object args);
}
[ComVisible(true), ClassInterface(ClassInterfaceType.None),
 ComDefaultInterface(typeof(IUpdateCompletion))]
public class UpdateCompletion : IUpdateCompletion {
    public void Invoke(object job, object args) {}
}
'@

function Invoke-WuaOperation($Worker, $Updates, [ValidateSet('Download', 'Install')][string]$Mode) {
    $Worker.Updates = $Updates
    $callback = New-Object UpdateCompletion
    $job = if ($Mode -eq 'Download') {
        $Worker.BeginDownload($callback, $callback, $null)
    } else {
        $Worker.BeginInstall($callback, $callback, $null)
    }
    try {
        while (!$job.IsCompleted) {
            $progress = $job.GetProgress()
            Write-Progress -Id 1 -Activity "$Mode Windows update" -Status $Updates.Item(0).Title `
                -PercentComplete ([Math]::Max(0, [Math]::Min(100, $progress.PercentComplete)))
            Start-Sleep -Milliseconds 500
        }
        if ($Mode -eq 'Download') { return $Worker.EndDownload($job) }
        return $Worker.EndInstall($job)
    } finally {
        if (!$job.IsCompleted) { $job.RequestAbort() }
        $job.CleanUp()
        Write-Progress -Id 1 -Activity "$Mode Windows update" -Completed
    }
}

Start-Transcript -Path $log | Out-Null
try {
    $beforeWindows = $null
    Invoke-Step 'Windows inventory' { $script:beforeWindows = Get-WindowsInventory }
    foreach ($source in @('winget', 'msstore')) {
        Invoke-Step "WinGet ($source)" {
            Invoke-Native 'winget.exe' @('upgrade', '--all', '--source', $source)
            Add-Result 'WinGet' $source 'Completed; package-level results are in the log.'
        }
    }
    Invoke-Step 'Microsoft Store updates' {
        $store = Get-Command 'store.exe' -CommandType Application -ErrorAction SilentlyContinue
        if ($null -eq $store) {
            throw 'Store CLI (store.exe) is unavailable. Update Microsoft Store and enable its Store CLI app execution alias, then rerun this script.'
        }
        Write-Host 'Applying available Store app updates...'
        Invoke-Native $store.Source @('updates', '--apply')
        Add-Result 'Store' 'App updates' 'Completed; package-level results are in the log.'
    }
    Invoke-Step 'Windows application changes' {
        if ($null -eq $beforeWindows) { throw 'Initial inventory unavailable; cannot determine application changes.' }
        Show-Changes 'Applications' $beforeWindows (Get-WindowsInventory)
    }
    Invoke-Step 'Ubuntu / Azure CLI / Snap' {
        & wsl.exe --exec bash -c '. /etc/os-release && [[ $ID == ubuntu ]]'
        if ($LASTEXITCODE -ne 0) { throw 'Set the default WSL distribution to Ubuntu before running this stage.' }
        $beforeUbuntu = Get-UbuntuInventory
        try {
            Invoke-Native 'wsl.exe' @('--exec', 'bash', '-c',
                'sudo apt-get update && sudo apt-get upgrade -y && sudo snap refresh && az upgrade --all true --allow-preview true --yes && cat /dev/null > ~/.bash_history && history -c && exit')
            Add-Result 'WSL' 'APT, Snap, Azure CLI' 'Completed; Snap/Azure CLI details are in the log.'
        } finally {
            Show-Changes 'WSL' $beforeUbuntu (Get-UbuntuInventory)
        }
    }
    Invoke-Step 'Windows Update' {
        $session = New-Object -ComObject Microsoft.Update.Session
        $session.ClientApplicationID = 'Interactive PowerShell updater'
        Write-Host 'Searching for applicable updates using the configured Windows Update service...'
        $search = $session.CreateUpdateSearcher().Search("IsInstalled=0 and IsHidden=0")
        if ($search.ResultCode -ne 2) { throw "Update search did not fully succeed (result $($search.ResultCode))." }
        Write-Host "`nChecking search results:"
        if (!$search.Updates.Count) { Add-Result 'Windows Update' 'Search' 'No applicable updates' }
        $downloader = $session.CreateUpdateDownloader()
        $installer = $session.CreateUpdateInstaller()
        $installer.AllowSourcePrompts = $false
        $installer.ForceQuiet = $true
        for ($i = 0; $i -lt $search.Updates.Count; $i++) {
            $update = $search.Updates.Item($i)
            $label = "$($update.Title) {$($update.Identity.UpdateID).$($update.Identity.RevisionNumber)}"
            try {
                if ($update.InstallationBehavior.CanRequestUserInput) {
                    Add-Result 'Windows Update' $label 'Skipped: requires interactive installer'
                    Write-Host "$($i + 1)> Skipped $label (requires interactive installer)"
                    continue
                }
                if (!(Confirm-Action "$($i + 1)> $label is applicable; do you want to install it?" $true)) {
                    Add-Result 'Windows Update' $label 'Declined'
                    continue
                }
                if (!$update.EulaAccepted) {
                    Write-Host $update.EulaText
                    if (!(Confirm-Action 'Accept this license agreement?')) {
                        Add-Result 'Windows Update' $label 'License declined'
                        continue
                    }
                    $update.AcceptEula()
                }
                Write-Host "$($i + 1)> Added $label"
                if ($installer.RebootRequiredBeforeInstallation) {
                    $script:reboot = $true
                    Add-Result 'Windows Update' $label 'Deferred: restart required before installation'
                    continue
                }
                # A single-update batch also accommodates exclusive updates.
                $batch = New-Object -ComObject Microsoft.Update.UpdateColl
                [void]$batch.Add($update)
                if (!$update.IsDownloaded) {
                    $download = Invoke-WuaOperation $downloader $batch Download
                    $detail = $download.GetUpdateResult(0)
                    if ($detail.ResultCode -ne 2 -or !$update.IsDownloaded) {
                        Add-Result 'Windows Update' $label "Download: $($resultNames[$detail.ResultCode]); HRESULT $($detail.HResult)"
                        continue
                    }
                }
                $install = Invoke-WuaOperation $installer $batch Install
                $detail = $install.GetUpdateResult(0)
                $script:reboot = $script:reboot -or $install.RebootRequired -or $detail.RebootRequired
                Add-Result 'Windows Update' $label "Install: $($resultNames[$detail.ResultCode]); HRESULT $($detail.HResult); restart: $($detail.RebootRequired)"
            } catch {
                Add-Result 'Windows Update' $label "Failed: $($_.Exception.Message)"
                Write-Warning "$label failed: $($_.Exception.Message)"
            }
        }
    }
    Invoke-Step 'Restart status' {
        $script:reboot = $script:reboot -or (New-Object -ComObject Microsoft.Update.SystemInfo).RebootRequired
        foreach ($path in @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
        )) {
            if (Test-Path $path) { $script:reboot = $true }
        }
    }
} finally {
    Write-Host "`n=== Detailed summary ===" -ForegroundColor Cyan
    $results | Format-List Area, Item, Result | Out-Host
    Write-Host "Restart required (detected): $reboot"
    Write-Host 'Version changes are observed changes, not proof that every package upgrade succeeded.'
    Write-Host 'Unchanged-version reinstalls and Snap details are available in the full log.'
    Write-Host "Full log: $log"
    Stop-Transcript | Out-Null
}

$restartApproved = Confirm-Action 'Restart Windows now? Save your work first.'
Complete-UpdateSession -Restart $restartApproved
[Environment]::Exit(0)
