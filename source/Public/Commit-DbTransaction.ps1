function Commit-DbTransaction {
    param([Parameter(Mandatory)][string]$Database, [System.Data.SQLite.SQLiteTransaction]$Transaction)
    if ($Transaction) { $Transaction.Commit(); $Transaction.Dispose(); return }
    Invoke-DbQuery -Database $Database -Query 'COMMIT' -NonQuery | Out-Null
}