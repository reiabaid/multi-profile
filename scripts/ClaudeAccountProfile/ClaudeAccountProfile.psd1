@{
    RootModule        = 'ClaudeAccountProfile.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'd85c5237-46d8-446c-8123-deb845d54633'
    Author            = 'reiabaid'
    Description       = 'Creates, lists, and removes isolated Claude Desktop account profiles (data folder + desktop shortcut per account) so multiple accounts can be signed in at once.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('New-ClaudeAccountProfile', 'Get-ClaudeAccountProfile', 'Remove-ClaudeAccountProfile')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
