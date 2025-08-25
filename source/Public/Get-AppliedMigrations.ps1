function Get-AppliedMigrations {
    param([Parameter(Mandatory)][string]$Database)
    Initialize-Db -Database $Database
    $rows = Invoke-DbQuery -Database $Database -Query "SELECT version FROM schema_migrations ORDER BY id"
    return $rows | ForEach-Object { $_.version }
}