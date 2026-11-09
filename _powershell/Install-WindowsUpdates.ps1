<#
.SYNOPSIS
Updates WSL, Ubuntu, application packages, and Windows.
.DESCRIPTION
WSL, Ubuntu, Winget, and Microsoft Store updates run before Windows Update confirmation.
Windows updates are listed before asking permission separately for each update to accept
its EULA, download, and install it. Declined updates are skipped. Installer dialogs are
allowed after confirmation. If a restart is required, Windows restarts only after a
separate final confirmation, even if updates were declined. Run in an elevated interactive console.
#>
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (!(New-Object Security.Principal.WindowsPrincipal $identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script in an elevated PowerShell console as your usual Windows user.'
}

function Write-UpdateProgress([string]$Stage, [string]$Status, [int]$PercentComplete = -1) {
    Write-Progress -Id 1 -Activity $Stage -Status $Status -PercentComplete $PercentComplete
}

function Invoke-Native([string]$File, [string[]]$Arguments, [int[]]$SuccessCodes = @(0), [switch]$WslUpdatePhases) {
    if ($WslUpdatePhases) {
        # Exact phase markers distinguish Ubuntu and Snap within the same history-cleanup trap.
        & $File @Arguments | ForEach-Object {
            switch -Exact ($_) {
                '__WINDOWS_UPDATE_PHASE_UBUNTU__' { Write-UpdateProgress 'Ubuntu update' 'Refreshing package lists and upgrading packages' }
                '__WINDOWS_UPDATE_PHASE_SNAP__' { Write-UpdateProgress 'Snap packages update' 'Refreshing Snap packages' }
                '__WINDOWS_UPDATE_PHASE_SNAP_SKIPPED__' {
                    Write-UpdateProgress 'Snap packages update' 'Skipped: Snap is not installed'
                    Write-Warning 'Snap packages update skipped: Snap is not installed.'
                }
                default { $_ }
            }
        }
    } else {
        & $File @Arguments
    }
    if ($LASTEXITCODE -notin $SuccessCodes) { throw "$File failed with exit code $LASTEXITCODE." }
}

$restart = $false
$restartRequired = $false
try {
    Write-UpdateProgress 'WSL update' 'Updating Windows Subsystem for Linux'
    Invoke-Native wsl.exe @('--update')
    Write-UpdateProgress 'Ubuntu update' 'Verifying the default WSL distribution is Ubuntu'
    Invoke-Native wsl.exe @('--exec', 'bash', '-c', '. /etc/os-release && [[ $ID == ubuntu ]]')
    Invoke-Native wsl.exe @('--exec', 'bash', '-c',
        'trap ''status=$?; history -c && : > ~/.bash_history || exit $?; unset HISTFILE; exit $status'' EXIT; printf ''%s\n'' ''__WINDOWS_UPDATE_PHASE_UBUNTU__''; sudo apt-get update && sudo apt-get upgrade -y && { if command -v snap >/dev/null; then printf ''%s\n'' ''__WINDOWS_UPDATE_PHASE_SNAP__''; sudo snap refresh; else printf ''%s\n'' ''__WINDOWS_UPDATE_PHASE_SNAP_SKIPPED__''; fi; }') -WslUpdatePhases

    foreach ($source in @('winget', 'msstore')) {
        if ($source -eq 'winget') {
            Write-UpdateProgress 'Winget updates' 'Upgrading packages from the winget source'
        } else {
            Write-UpdateProgress 'Microsoft Store updates' 'Upgrading packages from the msstore source'
        }
        Invoke-Native winget.exe @('upgrade', '--all', '--source', $source, '--accept-source-agreements', '--accept-package-agreements') @(0, -1978335189)
    }
    Write-UpdateProgress 'Microsoft Store updates' 'Applying updates with store.exe'
    Invoke-Native store.exe @('updates', '--apply')

    Write-UpdateProgress 'Windows Updates' 'Searching for available updates'
    $session = New-Object -ComObject Microsoft.Update.Session
    $search = $session.CreateUpdateSearcher().Search('IsInstalled=0 and IsHidden=0')
    if ($search.ResultCode -ne 2) { throw "Windows Update search failed: $($search.ResultCode)." }
    if ($search.Updates.Count -eq 0) {
        Write-UpdateProgress 'Windows Updates' 'No updates available' 100
        Write-Host 'No Windows updates available.'
    } else {
        Write-Host "Available Windows updates ($($search.Updates.Count)):"
        foreach ($update in $search.Updates) {
            Write-Host $update.Title
        }
        Write-Progress -Id 1 -Activity 'Windows Updates' -Completed
        $downloader = $session.CreateUpdateDownloader()
        $installer = $session.CreateUpdateInstaller()
        $installer.AllowSourcePrompts = $true
        $installer.ForceQuiet = $false
        $updateIndex = 0
        foreach ($update in $search.Updates) {
            # Progress measures processed updates, not download bytes or installer completion.
            $percentComplete = [int](100 * $updateIndex / $search.Updates.Count)
            $updateIndex++
            $updateStatus = "Update $updateIndex of $($search.Updates.Count): $($update.Title)"
            Write-UpdateProgress 'Windows Updates' $updateStatus $percentComplete
            if ($installer.RebootRequiredBeforeInstallation) {
                $restartRequired = $true
                Write-UpdateProgress 'Windows Updates' 'Restart required before remaining updates can be installed' $percentComplete
                Write-Warning 'Restart required before remaining Windows updates can be installed.'
                break
            }
            Write-Progress -Id 1 -Activity 'Windows Updates' -Completed
            $installUpdate = (Read-Host "Accept the EULA, download, and install '$($update.Title)'? Installer dialogs may require input. [y/N]") -match '^(y|yes)$'
            if (!$installUpdate) {
                Write-UpdateProgress 'Windows Updates' "Skipped - $updateStatus" ([int](100 * $updateIndex / $search.Updates.Count))
                Write-Host "Windows update declined: $($update.Title)"
                continue
            }
            if (!$update.EulaAccepted) { $update.AcceptEula() }
            $batch = New-Object -ComObject Microsoft.Update.UpdateColl
            [void]$batch.Add($update)
            if (!$update.IsDownloaded) {
                Write-UpdateProgress 'Windows Updates' "Downloading - $updateStatus" $percentComplete
                $downloader.Updates = $batch
                $download = $downloader.Download()
                if ($download.ResultCode -ne 2 -or $download.GetUpdateResult(0).ResultCode -ne 2) {
                    throw "Download failed for $($update.Title): $($download.GetUpdateResult(0).HResult)."
                }
            }
            Write-UpdateProgress 'Windows Updates' "Installing - $updateStatus" $percentComplete
            $installer.Updates = $batch
            $install = $installer.Install()
            if ($install.RebootRequired) { $restartRequired = $true }
            if ($install.ResultCode -ne 2 -or $install.GetUpdateResult(0).ResultCode -ne 2) {
                throw "Installation failed for $($update.Title): $($install.GetUpdateResult(0).HResult)."
            }
            Write-UpdateProgress 'Windows Updates' "Installed - $updateStatus" ([int](100 * $updateIndex / $search.Updates.Count))
        }
    }
    Write-Progress -Id 1 -Activity 'System updates' -Completed
    $systemInfo = New-Object -ComObject Microsoft.Update.SystemInfo
    if ($systemInfo.RebootRequired -or $restartRequired) {
        $restart = (Read-Host 'Save your work and close other shells. Restart Windows now? [y/N]') -match '^(y|yes)$'
    } else {
        Write-Host 'No Windows restart required.'
    }
} finally {
    Write-Progress -Id 1 -Activity 'System updates' -Completed
    if (Get-Command Get-PSReadLineOption -ErrorAction SilentlyContinue) {
        $historyPath = (Get-PSReadLineOption).HistorySavePath
        Set-PSReadLineOption -HistorySaveStyle SaveNothing
        [Microsoft.PowerShell.PSConsoleReadLine]::ClearHistory()
        if (Test-Path -LiteralPath $historyPath) { Set-Content -LiteralPath $historyPath -Value '' -NoNewline }
    }
    Clear-History
    Invoke-Native doskey.exe @('/reinstall', '/exename=cmd.exe')
}
if ($restart) { Restart-Computer }
