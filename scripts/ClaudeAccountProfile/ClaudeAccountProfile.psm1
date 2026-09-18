# Characters illegal in Windows filenames.
$script:InvalidNameChars = '[\\/:*?"<>|]'

function Test-ClaudeAccountNameValid {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )
    return -not ($Name -match $script:InvalidNameChars)
}

function Get-ClaudeShortcutPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string]$ShortcutRoot = [Environment]::GetFolderPath("Desktop")
    )
    return Join-Path $ShortcutRoot "Claude - $Name.lnk"
}

function Resolve-ClaudeExePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$Override
    )

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

function New-ClaudeAccountProfile {
    <#
    .SYNOPSIS
        Creates an isolated Claude Desktop profile folder and desktop shortcut
        for one or more named accounts.

    .PARAMETER AccountName
        One or more short labels for the accounts, e.g. "Work", "Personal".
        Names may not contain characters illegal in Windows filenames:
        \ / : * ? " < > |

    .PARAMETER Force
        Overwrite an existing profile folder and/or desktop shortcut for a
        given account name instead of warning and skipping it.

    .PARAMETER ClaudeExePath
        Path to Claude.exe. If omitted, the function tries to auto-detect it
        from the usual install location and the Start Menu shortcut.

    .PARAMETER ProfileRoot
        Where per-account data folders are created. Defaults to
        "$env:LOCALAPPDATA\ClaudeProfiles".

    .PARAMETER ShortcutRoot
        Where per-account desktop shortcuts are created. Defaults to the
        current user's Desktop folder.

    .OUTPUTS
        PSCustomObject with Name, ProfileDir, ShortcutPath, and Created
        (whether this call actually created/overwrote it, vs. skipped).

    .EXAMPLE
        New-ClaudeAccountProfile -AccountName "Work","Personal"
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$AccountName,

        [switch]$Force,

        [string]$ClaudeExePath,

        [string]$ProfileRoot = (Join-Path $env:LOCALAPPDATA "ClaudeProfiles"),

        [string]$ShortcutRoot = [Environment]::GetFolderPath("Desktop")
    )

    $validNames = @()
    foreach ($name in $AccountName) {
        if (Test-ClaudeAccountNameValid -Name $name) {
            $validNames += $name
        }
        else {
            Write-Warning "Skipping '$name': account names may not contain any of: \ / : * ? `" < > |"
        }
    }

    if (-not $validNames) {
        Write-Warning "No valid account names given."
        return
    }

    $exePath = Resolve-ClaudeExePath -Override $ClaudeExePath
    $shell = New-Object -ComObject WScript.Shell

    New-Item -ItemType Directory -Path $ProfileRoot -Force | Out-Null

    foreach ($name in $validNames) {
        $profileDir = Join-Path $ProfileRoot $name
        $shortcutPath = Get-ClaudeShortcutPath -Name $name -ShortcutRoot $ShortcutRoot

        $profileExists = Test-Path $profileDir
        $shortcutExists = Test-Path $shortcutPath

        if (($profileExists -or $shortcutExists) -and -not $Force) {
            Write-Warning "Skipping '$name': already exists (use -Force to overwrite). $(if ($profileExists) { "Profile folder: $profileDir. " })$(if ($shortcutExists) { "Shortcut: $shortcutPath." })"
            [PSCustomObject]@{
                Name         = $name
                ProfileDir   = $profileDir
                ShortcutPath = $shortcutPath
                Created      = $false
            }
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($name, "Create Claude account profile")) {
            [PSCustomObject]@{
                Name         = $name
                ProfileDir   = $profileDir
                ShortcutPath = $shortcutPath
                Created      = $false
            }
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

        [PSCustomObject]@{
            Name         = $name
            ProfileDir   = $profileDir
            ShortcutPath = $shortcutPath
            Created      = $true
        }
    }
}

function Get-ClaudeAccountProfile {
    <#
    .SYNOPSIS
        Lists existing Claude account profiles under -ProfileRoot.

    .PARAMETER ProfileRoot
        Where per-account data folders are created. Defaults to
        "$env:LOCALAPPDATA\ClaudeProfiles".

    .PARAMETER ShortcutRoot
        Where per-account desktop shortcuts are created. Defaults to the
        current user's Desktop folder.

    .OUTPUTS
        PSCustomObject with Name, ProfileDir, ShortcutPath, and ShortcutExists.

    .EXAMPLE
        Get-ClaudeAccountProfile
    #>
    [CmdletBinding()]
    param(
        [string]$ProfileRoot = (Join-Path $env:LOCALAPPDATA "ClaudeProfiles"),

        [string]$ShortcutRoot = [Environment]::GetFolderPath("Desktop")
    )

    if (-not (Test-Path $ProfileRoot)) {
        return
    }

    $profiles = Get-ChildItem -Path $ProfileRoot -Directory -ErrorAction SilentlyContinue
    foreach ($profile in $profiles) {
        $shortcutPath = Get-ClaudeShortcutPath -Name $profile.Name -ShortcutRoot $ShortcutRoot
        [PSCustomObject]@{
            Name            = $profile.Name
            ProfileDir      = $profile.FullName
            ShortcutPath    = $shortcutPath
            ShortcutExists  = Test-Path $shortcutPath
        }
    }
}

function Remove-ClaudeAccountProfile {
    <#
    .SYNOPSIS
        Removes the desktop shortcut and profile folder for one or more named
        Claude accounts.

    .PARAMETER AccountName
        One or more account names to remove.

    .PARAMETER ProfileRoot
        Where per-account data folders are created. Defaults to
        "$env:LOCALAPPDATA\ClaudeProfiles".

    .PARAMETER ShortcutRoot
        Where per-account desktop shortcuts are created. Defaults to the
        current user's Desktop folder.

    .OUTPUTS
        PSCustomObject with Name, ShortcutRemoved, and ProfileDirRemoved.

    .EXAMPLE
        Remove-ClaudeAccountProfile -AccountName "Work"
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$AccountName,

        [string]$ProfileRoot = (Join-Path $env:LOCALAPPDATA "ClaudeProfiles"),

        [string]$ShortcutRoot = [Environment]::GetFolderPath("Desktop")
    )

    foreach ($name in $AccountName) {
        if (-not (Test-ClaudeAccountNameValid -Name $name)) {
            Write-Warning "Skipping '$name': not a valid account name."
            continue
        }

        $profileDir = Join-Path $ProfileRoot $name
        $shortcutPath = Get-ClaudeShortcutPath -Name $name -ShortcutRoot $ShortcutRoot

        $shortcutRemoved = $false
        if (Test-Path $shortcutPath) {
            Remove-Item -Path $shortcutPath -Force
            $shortcutRemoved = $true
        }

        $profileDirRemoved = $false
        if (Test-Path $profileDir) {
            if ($PSCmdlet.ShouldProcess($profileDir, "Delete profile folder (contains session/login data)")) {
                Remove-Item -Path $profileDir -Recurse -Force
                $profileDirRemoved = $true
            }
        }

        [PSCustomObject]@{
            Name              = $name
            ShortcutRemoved   = $shortcutRemoved
            ProfileDirRemoved = $profileDirRemoved
        }
    }
}

Export-ModuleMember -Function New-ClaudeAccountProfile, Get-ClaudeAccountProfile, Remove-ClaudeAccountProfile
