# PSCsvSQLiteORM

PowerShell 5.1 ORM for SQLite with CSV import, schema inference, dynamic models, relationships, joins, upserts, and migrations.

## Installation

- From PowerShell Gallery (once published):
  - `Install-Module PSCsvSQLiteORM -Scope CurrentUser`
  - `Import-Module PSCsvSQLiteORM`
- Or from source:
  - `Install-Module PSSQLite -Scope CurrentUser` (dependency)
  - `./build-and-test.ps1`
  - `Import-Module .\output\PSCsvSQLiteORM`

## Quick Start

1) Initialize logging and defaults (optional, recommended)

```
Initialize-ORMVars -LogLevel INFO -LogPath 'C:\\path\\db.log'
# Or via settings: Initialize-ORMVars -SettingsPath .\source\Examples\orm.settings.ps1
```

2) Import CSVs (schema inferred; see SchemaMode)

```
$db = '.\sample.db'
Import-CsvToSqlite -CsvPath .\Tests\assets.csv -Database $db -TableName assets -SchemaMode Relaxed
Import-CsvToSqlite -CsvPath .\Tests\vulns.csv  -Database $db -TableName vulns  -SchemaMode Relaxed
```

3) Discover and confirm relationships

```
$suggested = Find-DbRelationships -Database $db
# Optionally confirm a FK using triggers for enforcement
# Confirm-DbForeignKey -Database $db -From 'vulns' -Column 'asset_id' -To 'assets' -RefColumn 'id' -OnDelete CASCADE
```

4) Generate and load dynamic models

```
$types = Export-DynamicModelsFromCatalog -Database $db
Set-DynamicORMClass
```

5) Use query builder or dynamic models

```
# Query builder
New-DbQuery -Database $db -From 'assets' |
  % { $_.Where('hostname LIKE @h', @{ h = 'server%' }).Select(@('id','hostname')).OrderBy('id ASC').Run() }

# Dynamic model
$Asset = [DynamicAssets]::new($db)
($Asset.Where('hostname = @h', @{ h='server01' })).Count
```

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

- Example settings file to copy: `source/Examples/orm.settings.ps1`
  - Usage: `Initialize-ORMVars -SettingsPath (Join-Path $PSScriptRoot 'source/Examples/orm.settings.ps1')`

## AppendOnly schema mode

- `Import-CsvToSqlite -SchemaMode AppendOnly` prohibits schema changes and skips table creation.
- If the table does not exist, the command throws.

## RIGHT/FULL join emulation

The query builder supports INNER and LEFT joins natively. RIGHT and FULL joins are emulated:
- RIGHT JOIN: internally swapped into LEFT JOIN
- FULL OUTER JOIN: emulated via `LEFT JOIN A->B UNION LEFT JOIN B->A`

Limitations: currently supports at most one RIGHT/FULL join per query.

Example:

```
$q = New-DbQuery -Database $db -From 'a'
$q = $q.Join('b', 'a.id = b.a_id', 'Right').Select(@('a.id as aid','b.id as bid'))
$rows = $q.Run()
```

## Transactions

- If `.NET System.Data.SQLite` is available, explicit transactions are supported via `Start-DbTransaction`, `Complete-DbTransaction`, and `Undo-DbTransaction`.
- In fallback mode (PSSQLite), commands execute on ad-hoc connections; multi-statement transactions are not guaranteed.

## Tips

- Use `Close-DbConnections` to release open ADO.NET connections (useful before deleting/replacing a database file).
- Module targets Windows PowerShell 5.1; `PSSQLite` is a required dependency.

