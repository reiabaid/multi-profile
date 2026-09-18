<#
.SYNOPSIS
    Creates isolated, simultaneously-launchable Claude Desktop profiles.

.DESCRIPTION
    For each account name given, creates a dedicated user-data folder and a
    desktop shortcut that launches Claude Desktop pointed at that folder via
    the Electron/Chromium --user-data-dir switch. Because each shortcut uses
    a separate data folder, you can have several shortcuts open at the same
    time, each signed into a different account.

    This relies on Claude Desktop's underlying Electron shell honoring the
    standard --user-data-dir switch. It is not an officially documented
    Anthropic feature, so a future app update could change or break it -
    re-run this script (or re-check the shortcuts) after updating Claude.

.PARAMETER AccountName
    One or more short labels for the accounts, e.g. "Work", "Personal".
    Each gets its own profile folder and desktop shortcut.

.PARAMETER ClaudeExePath
    Path to Claude.exe. If omitted, the script tries to auto-detect it from
    the usual install location and the Start Menu shortcut.

.PARAMETER ProfileRoot
    Where per-account data folders are created. Defaults to
    "$env:LOCALAPPDATA\ClaudeProfiles".

.EXAMPLE
    .\New-ClaudeAccountProfile.ps1 -AccountName "Work","Personal"

    Creates two isolated profiles and two desktop shortcuts, "Claude - Work"
    and "Claude - Personal", that can both be open at once.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$AccountName,

    [string]$ClaudeExePath,

    [string]$ProfileRoot = (Join-Path $env:LOCALAPPDATA "ClaudeProfiles")
)

function Resolve-ClaudeExePath {
    param([string]$Override)

    if ($Override) {
        if (Test-Path $Override) { return (Resolve-Path $Override).Path }
        throw "No file found at -ClaudeExePath '$Override'."
    }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "AnthropicClaude\Claude.exe")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }

    $startMenuShortcut = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Claude.lnk"
    if (Test-Path $startMenuShortcut) {
        $shell = New-Object -ComObject WScript.Shell
        $target = $shell.CreateShortcut($startMenuShortcut).TargetPath
        if ($target -and (Test-Path $target)) { return $target }
    }

    throw "Could not find Claude.exe automatically. Re-run with -ClaudeExePath '<full path to Claude.exe>'."
}

$exePath = Resolve-ClaudeExePath -Override $ClaudeExePath
$desktopPath = [Environment]::GetFolderPath("Desktop")
$shell = New-Object -ComObject WScript.Shell

New-Item -ItemType Directory -Path $ProfileRoot -Force | Out-Null

foreach ($name in $AccountName) {
    $profileDir = Join-Path $ProfileRoot $name
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null

    $shortcutPath = Join-Path $desktopPath "Claude - $name.lnk"
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $exePath
    $shortcut.Arguments = "--user-data-dir=`"$profileDir`""
    $shortcut.WorkingDirectory = Split-Path $exePath -Parent
    $shortcut.IconLocation = $exePath
    $shortcut.Description = "Claude Desktop - isolated profile for '$name'"
    $shortcut.Save()

    Write-Host "Created '$shortcutPath' -> profile data at '$profileDir'"
}

Write-Host ""
Write-Host "Done. Each shortcut above can be launched independently, and several"
Write-Host "can be open at the same time since each uses its own data folder."
Write-Host "Sign into a different account from each shortcut on first launch."
