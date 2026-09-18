# Claude Desktop simultaneous multi-account shortcuts

`New-ClaudeAccountProfile.ps1` creates one isolated data folder and one desktop
shortcut per named account, so you can have Claude Desktop open more than once
at the same time, each window signed into a different account.

## How it works

Claude Desktop is an Electron app, and Electron/Chromium apps read a
`--user-data-dir=<path>` command-line switch that redirects where a launch
stores its session data (cookies, local storage, login state, etc.). Each
shortcut this script creates points at its own folder under
`%LOCALAPPDATA%\ClaudeProfiles\<AccountName>` and passes that folder via
`--user-data-dir`, so the windows never share state and can run concurrently.

This is **not** an officially documented Anthropic feature. It's a standard
Electron/Chromium switch that happens to work today. Treat it as unconfirmed:
re-check your shortcuts after a Claude Desktop update in case the behavior
changes.

## Usage

From a Windows PowerShell prompt:

```powershell
.\New-ClaudeAccountProfile.ps1 -AccountName "Work","Personal"
```

This creates:

- `Claude - Work.lnk` and `Claude - Personal.lnk` on your Desktop
- `%LOCALAPPDATA%\ClaudeProfiles\Work` and `...\Personal` as their data folders

Launch both shortcuts and sign into a different account in each window the
first time. After that, each shortcut remembers its own login.

### Options

- `-ClaudeExePath <path>` - point at `Claude.exe` explicitly if auto-detection
  fails (the script checks the default install path and the Start Menu
  shortcut).
- `-ProfileRoot <path>` - change where profile data folders are created
  (default: `%LOCALAPPDATA%\ClaudeProfiles`).
- `-Force` - overwrite an existing profile folder and/or desktop shortcut for
  an account name instead of warning and skipping it.

Account names may not contain characters that are illegal in Windows
filenames: `\ / : * ? " < > |`. By default, if a profile folder or shortcut
already exists for a given name, the script warns and skips it rather than
overwriting; pass `-Force` to overwrite anyway.

## Listing accounts

```powershell
.\New-ClaudeAccountProfile.ps1 -List
```

Prints every account profile folder found under `-ProfileRoot` (default
`%LOCALAPPDATA%\ClaudeProfiles`), along with whether its matching desktop
shortcut still exists.

## Removing an account

```powershell
.\New-ClaudeAccountProfile.ps1 -Remove "Work"
```

Deletes the account's desktop shortcut and prompts for confirmation before
deleting its profile folder (since it holds session/login data). Accepts
multiple names at once, e.g. `-Remove "Work","Personal"`.

You can also do this manually: delete the shortcut and its folder under
`%LOCALAPPDATA%\ClaudeProfiles`.

## Alternatives considered

- **Session-snapshot switcher** (e.g. claude-account-switcher-style tools):
  saves/restores a snapshot into Claude's single default data folder. Simpler,
  but only one account can be signed in at a time - switching requires closing
  and reopening the app.
- **Separate Windows user accounts**: the most guaranteed-to-work isolation
  (each Windows user has entirely separate app data), usable with Fast User
  Switching, but requires managing a second OS-level login instead of a single
  click.

This script is for the "both accounts open at once" case, trading an
unofficial flag for convenience.
