function Rollback-DbTransaction {
    param([Parameter(Mandatory)][string]$Database, [System.Data.SQLite.SQLiteTransaction]$Transaction)
    if ($Transaction) { $Transaction.Rollback(); $Transaction.Dispose(); return }
    Invoke-DbQuery -Database $Database -Query 'ROLLBACK' -NonQuery | Out-Null
}