function Undo-DbTransaction {
    param([Parameter(Mandatory)][string]$Database, [System.Data.SQLite.SQLiteTransaction]$Transaction)
    if ($Transaction) { $Transaction.Rollback(); $Transaction.Dispose(); return }
    # Fallback path without transaction object: no-op
}

