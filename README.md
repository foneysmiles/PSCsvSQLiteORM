# PSCsvSQLiteORM

PowerShell 5.1 ORM for SQLite with CSV import, schema inference, dynamic models, relationships, joins, upserts, and migrations.

## Quick Start

- Install dependency: `Install-Module PSSQLite -Scope CurrentUser`
- Build/import module: `./build-and-test.ps1` or `Import-Module .\output\PSCsvSQLiteORM`
- Initialize logging and defaults:
  - `Initialize-ORMVars -LogLevel DEBUG -LogPath 'C:\\path\\db.log'`
- Import CSVs:
  - `Import-CsvToSqlite -CsvPath .\Tests\assets.csv -Database .\sample.db -TableName assets`
- Update catalog and generate models:
  - `$types = Export-DynamicModelsFromCatalog -Database .\sample.db`
  - `Set-DynamicORMClass`

## Settings Script

You can configure ORM defaults via a settings script that returns a hashtable:

```
@{
  DbPath   = 'C:\\data\\app.db'
  LogPath  = 'C:\\logs\\db.log'
  LogLevel = 'INFO' # DEBUG | INFO | WARN | ERROR
}
```

Apply it:

`Initialize-ORMVars -SettingsPath .\orm.settings.ps1`

Explicit parameters override settings in the file.

## AppendOnly schema mode

- `Import-CsvToSqlite -SchemaMode AppendOnly` prohibits schema changes and skips table creation.
- If the table does not exist, the command throws.

## RIGHT/FULL join emulation

The query builder supports INNER and LEFT joins natively. RIGHT and FULL joins are emulated:
- RIGHT JOIN: internally swapped into LEFT JOIN
- FULL OUTER JOIN: emulated via `LEFT JOIN A->B UNION LEFT JOIN B->A`

Limitations: currently supports at most one RIGHT/FULL join per query.

