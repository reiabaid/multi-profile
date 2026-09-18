<#
.SYNOPSIS
    Creates, lists, or removes isolated, simultaneously-launchable Claude
    Desktop profiles.

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

    Besides creating profiles, the script can also list existing profiles
    (-List) or remove them (-Remove).

.PARAMETER AccountName
    One or more short labels for the accounts, e.g. "Work", "Personal".
    Each gets its own profile folder and desktop shortcut. Names may not
    contain characters that are illegal in Windows filenames: \ / : * ? " < > |

.PARAMETER ClaudeExePath
    Path to Claude.exe. If omitted, the script tries to auto-detect it from
    the usual install location and the Start Menu shortcut.

.PARAMETER ProfileRoot
    Where per-account data folders are created. Defaults to
    "$env:LOCALAPPDATA\ClaudeProfiles".

.PARAMETER Force
    When creating profiles, overwrite an existing profile folder and/or
    desktop shortcut for a given account name instead of warning and
    skipping it.

.PARAMETER List
    List every existing account profile found under -ProfileRoot, along with
    whether its matching desktop shortcut still exists. Ignores -AccountName.

.PARAMETER Remove
    Delete the desktop shortcut and profile folder for the given account
    name(s). Prompts for confirmation before deleting each profile folder,
    since it holds session/login data.

.EXAMPLE
    .\New-ClaudeAccountProfile.ps1 -AccountName "Work","Personal"

    Creates two isolated profiles and two desktop shortcuts, "Claude - Work"
    and "Claude - Personal", that can both be open at once.

.EXAMPLE
    .\New-ClaudeAccountProfile.ps1 -List

    Lists every account profile under the default -ProfileRoot and whether
    its desktop shortcut still exists.

.EXAMPLE
    .\New-ClaudeAccountProfile.ps1 -Remove "Work"

    Deletes the "Claude - Work" desktop shortcut and prompts to delete the
    "Work" profile folder.
#>
[CmdletBinding(DefaultParameterSetName = 'Create', SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Create')]
    [ValidateNotNullOrEmpty()]
    [string[]]$AccountName,

    [Parameter(ParameterSetName = 'Create')]
    [switch]$Force,

    [Parameter(ParameterSetName = 'Create')]
    [string]$ClaudeExePath,

    [Parameter(Mandatory = $true, ParameterSetName = 'List')]
    [switch]$List,

    [Parameter(Mandatory = $true, ParameterSetName = 'Remove')]
    [ValidateNotNullOrEmpty()]
    [string[]]$Remove,

    [Parameter(ParameterSetName = 'Create')]
    [Parameter(ParameterSetName = 'List')]
    [Parameter(ParameterSetName = 'Remove')]
    [string]$ProfileRoot = (Join-Path $env:LOCALAPPDATA "ClaudeProfiles")
)

# Characters illegal in Windows filenames.
$script:InvalidNameChars = '[\\/:*?"<>|]'

function Test-ValidAccountName {
    param([string]$Name)
    return -not ($Name -match $script:InvalidNameChars)
}

function Get-ShortcutPath {
    param([string]$Name)
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    return Join-Path $desktopPath "Claude - $Name.lnk"
}

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

function Invoke-CreateProfiles {
    foreach ($name in $AccountName) {
        if (-not (Test-ValidAccountName $name)) {
            Write-Warning "Skipping '$name': account names may not contain any of: \ / : * ? `" < > |"
            continue
        }
    }

    $validNames = $AccountName | Where-Object { Test-ValidAccountName $_ }
    if (-not $validNames) {
        Write-Warning "No valid account names given."
        return
    }

    $exePath = Resolve-ClaudeExePath -Override $ClaudeExePath
    $shell = New-Object -ComObject WScript.Shell

    New-Item -ItemType Directory -Path $ProfileRoot -Force | Out-Null

    foreach ($name in $validNames) {
        $profileDir = Join-Path $ProfileRoot $name
        $shortcutPath = Get-ShortcutPath -Name $name

        $profileExists = Test-Path $profileDir
        $shortcutExists = Test-Path $shortcutPath

        if (($profileExists -or $shortcutExists) -and -not $Force) {
            Write-Warning "Skipping '$name': already exists (use -Force to overwrite). $(if ($profileExists) { "Profile folder: $profileDir. " })$(if ($shortcutExists) { "Shortcut: $shortcutPath." })"
            continue
        }

        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null

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
}

function Invoke-ListProfiles {
    if (-not (Test-Path $ProfileRoot)) {
        Write-Host "No profile root found at '$ProfileRoot'."
        return
    }

    $profiles = Get-ChildItem -Path $ProfileRoot -Directory -ErrorAction SilentlyContinue
    if (-not $profiles) {
        Write-Host "No account profiles found under '$ProfileRoot'."
        return
    }

    foreach ($profile in $profiles) {
        $shortcutPath = Get-ShortcutPath -Name $profile.Name
        $shortcutStatus = if (Test-Path $shortcutPath) { "shortcut present" } else { "shortcut MISSING" }
        Write-Host "$($profile.Name) -> $($profile.FullName) (${shortcutStatus}: $shortcutPath)"
    }
}

function Invoke-RemoveProfiles {
    foreach ($name in $Remove) {
        if (-not (Test-ValidAccountName $name)) {
            Write-Warning "Skipping '$name': not a valid account name."
            continue
        }

        $profileDir = Join-Path $ProfileRoot $name
        $shortcutPath = Get-ShortcutPath -Name $name

        if (Test-Path $shortcutPath) {
            Remove-Item -Path $shortcutPath -Force
            Write-Host "Removed shortcut '$shortcutPath'"
        }
        else {
            Write-Host "No shortcut found at '$shortcutPath'"
        }

        if (Test-Path $profileDir) {
            if ($PSCmdlet.ShouldProcess($profileDir, "Delete profile folder (contains session/login data)")) {
                Remove-Item -Path $profileDir -Recurse -Force
                Write-Host "Removed profile folder '$profileDir'"
            }
            else {
                Write-Host "Skipped deleting profile folder '$profileDir'"
            }
        }
        else {
            Write-Host "No profile folder found at '$profileDir'"
        }
    }
}

switch ($PSCmdlet.ParameterSetName) {
    'List' { Invoke-ListProfiles }
    'Remove' { Invoke-RemoveProfiles }
    default { Invoke-CreateProfiles }
}
