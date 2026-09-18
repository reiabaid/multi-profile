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

    This script is a thin command-line wrapper around the ClaudeAccountProfile
    module (in the ClaudeAccountProfile subfolder), which can also be
    installed and used directly via Import-Module for scripting/automation.

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

Import-Module (Join-Path $PSScriptRoot "ClaudeAccountProfile\ClaudeAccountProfile.psd1") -Force

# Forward -WhatIf/-Confirm to the module functions only if the caller explicitly
# passed them (module functions live in their own session state, so the
# $WhatIfPreference/$ConfirmPreference of this script's scope won't reach them
# automatically).
$shouldProcessParams = @{}
if ($PSBoundParameters.ContainsKey('WhatIf')) { $shouldProcessParams.WhatIf = $PSBoundParameters['WhatIf'] }
if ($PSBoundParameters.ContainsKey('Confirm')) { $shouldProcessParams.Confirm = $PSBoundParameters['Confirm'] }

switch ($PSCmdlet.ParameterSetName) {
    'List' {
        $profiles = Get-ClaudeAccountProfile -ProfileRoot $ProfileRoot
        if (-not $profiles) {
            Write-Host "No account profiles found under '$ProfileRoot'."
            break
        }
        foreach ($profile in $profiles) {
            $shortcutStatus = if ($profile.ShortcutExists) { "shortcut present" } else { "shortcut MISSING" }
            Write-Host "$($profile.Name) -> $($profile.ProfileDir) (${shortcutStatus}: $($profile.ShortcutPath))"
        }
    }

    'Remove' {
        foreach ($result in (Remove-ClaudeAccountProfile -AccountName $Remove -ProfileRoot $ProfileRoot @shouldProcessParams)) {
            if ($result.ShortcutRemoved) { Write-Host "Removed shortcut for '$($result.Name)'" }
            if ($result.ProfileDirRemoved) { Write-Host "Removed profile folder for '$($result.Name)'" }
        }
    }

    default {
        $results = New-ClaudeAccountProfile -AccountName $AccountName -Force:$Force -ClaudeExePath $ClaudeExePath -ProfileRoot $ProfileRoot @shouldProcessParams
        foreach ($result in $results) {
            if ($result.Created) {
                Write-Host "Created '$($result.ShortcutPath)' -> profile data at '$($result.ProfileDir)'"
            }
        }

        Write-Host ""
        Write-Host "Done. Each shortcut above can be launched independently, and several"
        Write-Host "can be open at the same time since each uses its own data folder."
        Write-Host "Sign into a different account from each shortcut on first launch."
    }
}
