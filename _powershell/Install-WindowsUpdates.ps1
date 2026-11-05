$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (!(New-Object Security.Principal.WindowsPrincipal $identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script in an elevated PowerShell console as your usual Windows user.'
}

function Invoke-Native([string]$File, [string[]]$Arguments, [int[]]$SuccessCodes = @(0)) {
    & $File @Arguments
    if ($LASTEXITCODE -notin $SuccessCodes) { throw "$File failed with exit code $LASTEXITCODE." }
}

$restart = $false
try {
    Invoke-Native wsl.exe @('--update')
    Invoke-Native wsl.exe @('--exec', 'bash', '-c', '. /etc/os-release && [[ $ID == ubuntu ]]')
    Invoke-Native wsl.exe @('--exec', 'bash', '-c',
        'trap ''status=$?; history -c && : > ~/.bash_history || exit $?; unset HISTFILE; exit $status'' EXIT; sudo apt-get update && sudo apt-get upgrade -y && { if command -v snap >/dev/null; then sudo snap refresh; fi; }')

    foreach ($source in @('winget', 'msstore')) {
        Invoke-Native winget.exe @('upgrade', '--all', '--source', $source, '--accept-source-agreements', '--accept-package-agreements') @(0, -1978335189)
    }
    Invoke-Native store.exe @('updates', '--apply')

    $session = New-Object -ComObject Microsoft.Update.Session
    $search = $session.CreateUpdateSearcher().Search('IsInstalled=0 and IsHidden=0')
    if ($search.ResultCode -ne 2) { throw "Windows Update search failed: $($search.ResultCode)." }
    $downloader = $session.CreateUpdateDownloader()
    $installer = $session.CreateUpdateInstaller()
    $installer.AllowSourcePrompts = $false
    $installer.ForceQuiet = $true
    foreach ($update in $search.Updates) {
        Write-Host $update.Title
        if ($update.InstallationBehavior.CanRequestUserInput) {
            Write-Warning 'Skipped: update requires an interactive installer.'
            continue
        }
        if ($installer.RebootRequiredBeforeInstallation) {
            Write-Warning 'Restart required before remaining Windows updates can be installed.'
            break
        }
        if (!$update.EulaAccepted) { $update.AcceptEula() }
        $batch = New-Object -ComObject Microsoft.Update.UpdateColl
        [void]$batch.Add($update)
        if (!$update.IsDownloaded) {
            $downloader.Updates = $batch
            $download = $downloader.Download()
            if ($download.ResultCode -ne 2 -or $download.GetUpdateResult(0).ResultCode -ne 2) {
                throw "Download failed for $($update.Title): $($download.GetUpdateResult(0).HResult)."
            }
        }
        $installer.Updates = $batch
        $install = $installer.Install()
        if ($install.ResultCode -ne 2 -or $install.GetUpdateResult(0).ResultCode -ne 2) {
            throw "Installation failed for $($update.Title): $($install.GetUpdateResult(0).HResult)."
        }
    }
    $restart = (Read-Host 'Save your work and close other shells. Restart Windows now? [y/N]') -match '^(y|yes)$'
} finally {
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
