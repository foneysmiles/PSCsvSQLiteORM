function Ensure-ForeignKeysPragma {
    param([Parameter(Mandatory)][string]$Database)
    if ($script:PragmaSet[$Database]) { return }
    try {
        Invoke-SqliteQuery -DataSource $Database -Query 'PRAGMA foreign_keys = ON;'
        $script:PragmaSet[$Database] = $true
        Write-DbLog DEBUG "PRAGMA foreign_keys = ON (fallback)"
    }
    catch { Write-DbLog WARN "Unable to set PRAGMA foreign_keys in fallback" $_.Exception }
}