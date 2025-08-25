function Initialize-Db {
    param([Parameter(Mandatory)][string]$Database)
    @"
CREATE TABLE IF NOT EXISTS schema_migrations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    version TEXT NOT NULL UNIQUE,
    applied_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS __tables__ (
    table_name TEXT PRIMARY KEY,
    source TEXT,
    created_at TEXT,
    csv_hash TEXT,
    rowcount INTEGER,
    sample_json TEXT
);
CREATE TABLE IF NOT EXISTS __columns__ (
    table_name TEXT,
    column_name TEXT,
    data_type TEXT,
    nullable INTEGER,
    pk INTEGER,
    example_values_json TEXT,
    PRIMARY KEY (table_name, column_name)
);
CREATE TABLE IF NOT EXISTS __fks__ (
    table_name TEXT,
    column_name TEXT,
    ref_table TEXT,
    ref_column TEXT,
    confidence REAL,
    status TEXT,
    on_delete TEXT,
    on_update TEXT,
    PRIMARY KEY (table_name, column_name)
);
"@ | ForEach-Object { Invoke-DbQuery -Database $Database -Query $_ -NonQuery | Out-Null }
}