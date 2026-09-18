#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'ClaudeAccountProfile.psd1') -Force

    $script:ProfileRoot = Join-Path $TestDrive 'Profiles'
    $script:ShortcutRoot = Join-Path $TestDrive 'Desktop'
    New-Item -ItemType Directory -Path $ShortcutRoot -Force | Out-Null

    $script:FakeExe = Join-Path $TestDrive 'Claude.exe'
    Set-Content -Path $FakeExe -Value 'not a real executable'
}

Describe 'Test-ClaudeAccountNameValid' {
    It 'accepts an ordinary name' {
        InModuleScope ClaudeAccountProfile {
            Test-ClaudeAccountNameValid -Name 'Work' | Should -BeTrue
        }
    }

    It 'rejects names containing <_>' -ForEach @('\', '/', ':', '*', '?', '"', '<', '>', '|') {
        $char = $_
        InModuleScope ClaudeAccountProfile -Parameters @{ Char = $char } {
            Test-ClaudeAccountNameValid -Name "Bad${Char}Name" | Should -BeFalse
        }
    }
}

Describe 'New-ClaudeAccountProfile' {
    It 'creates a profile folder and a shortcut' {
        $result = New-ClaudeAccountProfile -AccountName 'Alpha' -ClaudeExePath $FakeExe -ProfileRoot $ProfileRoot -ShortcutRoot $ShortcutRoot

        $result.Created | Should -BeTrue
        Test-Path (Join-Path $ProfileRoot 'Alpha') | Should -BeTrue
        Test-Path $result.ShortcutPath | Should -BeTrue
    }

    It 'skips an existing profile without -Force' {
        New-ClaudeAccountProfile -AccountName 'Beta' -ClaudeExePath $FakeExe -ProfileRoot $ProfileRoot -ShortcutRoot $ShortcutRoot | Out-Null

        $result = New-ClaudeAccountProfile -AccountName 'Beta' -ClaudeExePath $FakeExe -ProfileRoot $ProfileRoot -ShortcutRoot $ShortcutRoot -WarningAction SilentlyContinue

        $result.Created | Should -BeFalse
    }

    It 'overwrites an existing profile with -Force' {
        New-ClaudeAccountProfile -AccountName 'Gamma' -ClaudeExePath $FakeExe -ProfileRoot $ProfileRoot -ShortcutRoot $ShortcutRoot | Out-Null

        $result = New-ClaudeAccountProfile -AccountName 'Gamma' -Force -ClaudeExePath $FakeExe -ProfileRoot $ProfileRoot -ShortcutRoot $ShortcutRoot

        $result.Created | Should -BeTrue
    }

    It 'rejects an account name with illegal characters and creates nothing' {
        $result = New-ClaudeAccountProfile -AccountName 'Bad:Name' -ClaudeExePath $FakeExe -ProfileRoot $ProfileRoot -ShortcutRoot $ShortcutRoot -WarningAction SilentlyContinue

        $result | Should -BeNullOrEmpty
        Test-Path (Join-Path $ProfileRoot 'Bad:Name') | Should -BeFalse
    }

    It 'does not create anything under -WhatIf' {
        $result = New-ClaudeAccountProfile -AccountName 'Delta' -ClaudeExePath $FakeExe -ProfileRoot $ProfileRoot -ShortcutRoot $ShortcutRoot -WhatIf

        $result.Created | Should -BeFalse
        Test-Path (Join-Path $ProfileRoot 'Delta') | Should -BeFalse
    }
}

Describe 'Get-ClaudeAccountProfile' {
    BeforeAll {
        New-ClaudeAccountProfile -AccountName 'Listed' -ClaudeExePath $FakeExe -ProfileRoot $ProfileRoot -ShortcutRoot $ShortcutRoot | Out-Null
    }

    It 'lists a created profile with its shortcut status' {
        $profiles = Get-ClaudeAccountProfile -ProfileRoot $ProfileRoot -ShortcutRoot $ShortcutRoot
        $listed = $profiles | Where-Object Name -EQ 'Listed'

        $listed | Should -Not -BeNullOrEmpty
        $listed.ShortcutExists | Should -BeTrue
    }

    It 'reports a missing shortcut when the .lnk was deleted' {
        $shortcutPath = (Get-ClaudeAccountProfile -ProfileRoot $ProfileRoot -ShortcutRoot $ShortcutRoot | Where-Object Name -EQ 'Listed').ShortcutPath
        Remove-Item -Path $shortcutPath -Force

        $listed = Get-ClaudeAccountProfile -ProfileRoot $ProfileRoot -ShortcutRoot $ShortcutRoot | Where-Object Name -EQ 'Listed'

        $listed.ShortcutExists | Should -BeFalse
    }

    It 'returns nothing when -ProfileRoot does not exist' {
        Get-ClaudeAccountProfile -ProfileRoot (Join-Path $TestDrive 'DoesNotExist') | Should -BeNullOrEmpty
    }
}

Describe 'Remove-ClaudeAccountProfile' {
    BeforeEach {
        New-ClaudeAccountProfile -AccountName 'Removable' -Force -ClaudeExePath $FakeExe -ProfileRoot $ProfileRoot -ShortcutRoot $ShortcutRoot | Out-Null
    }

    It 'removes the shortcut and profile folder when confirmed' {
        $result = Remove-ClaudeAccountProfile -AccountName 'Removable' -ProfileRoot $ProfileRoot -ShortcutRoot $ShortcutRoot -Confirm:$false

        $result.ShortcutRemoved | Should -BeTrue
        $result.ProfileDirRemoved | Should -BeTrue
        Test-Path (Join-Path $ProfileRoot 'Removable') | Should -BeFalse
    }

    It 'keeps the profile folder when -WhatIf is used' {
        $result = Remove-ClaudeAccountProfile -AccountName 'Removable' -ProfileRoot $ProfileRoot -ShortcutRoot $ShortcutRoot -WhatIf

        $result.ProfileDirRemoved | Should -BeFalse
        Test-Path (Join-Path $ProfileRoot 'Removable') | Should -BeTrue
    }

    It 'is a no-op for a name that does not exist' {
        $result = Remove-ClaudeAccountProfile -AccountName 'NeverExisted' -ProfileRoot $ProfileRoot -ShortcutRoot $ShortcutRoot -Confirm:$false

        $result.ShortcutRemoved | Should -BeFalse
        $result.ProfileDirRemoved | Should -BeFalse
    }
}
