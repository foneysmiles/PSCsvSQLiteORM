function Add-DbMigration {
    param([Parameter(Mandatory)][string]$Database, [Parameter(Mandatory)][string]$Version, [Parameter(Mandatory)][scriptblock]$Up, [scriptblock]$Down)
    Initialize-Db -Database $Database
    $applied = Get-AppliedMigrations -Database $Database
    if ($applied -contains $Version) { Write-DbLog INFO "Migration $Version already applied."; return }
    $tx = Start-DbTransaction -Database $Database
    try {
        & $Up $Database
        Invoke-DbQuery -Database $Database -Query "INSERT INTO schema_migrations(version, applied_at) VALUES(@v, @t)" -SqlParameters @{ v = $Version; t = (Get-Date).ToString('s') } -NonQuery | Out-Null
        Complete-DbTransaction -Database $Database -Transaction $tx; Write-DbLog INFO "Applied migration $Version"
    }
    catch { Undo-DbTransaction -Database $Database -Transaction $tx; Write-DbLog ERROR "Migration $Version failed" $_.Exception; throw }
}
