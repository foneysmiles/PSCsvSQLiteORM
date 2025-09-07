# PSCsvSQLiteORM

PowerShell 5.1 ORM for SQLite with CSV import, schema inference, dynamic models, relationships, joins, upserts, and migrations.

## Quick Start

### 1. Install Dependencies
```powershell
# Install required PSSQLite module
Install-Module PSSQLite -Scope CurrentUser

# Install PSCsvSQLiteORM from PowerShell Gallery (latest version)
Install-Module PSCsvSQLiteORM -Scope CurrentUser

# Or install specific version 3.1.3
Install-Module PSCsvSQLiteORM -RequiredVersion 3.1.3 -Scope CurrentUser
```

### 2. Initialize the ORM
```powershell
# Import the module
Import-Module PSCsvSQLiteORM

# Initialize with logging (optional but recommended)
Initialize-ORMVars -LogLevel DEBUG -LogPath 'C:\temp\orm.log'

# Or use a settings file for configuration
Initialize-ORMVars -SettingsPath .\orm.settings.ps1
```

### 3. Import CSV Data
```powershell
# Import a CSV file into SQLite database
Import-CsvToSqlite -CsvPath .\data\assets.csv -Database .\myapp.db -TableName assets

# Import with specific schema mode (optional)
Import-CsvToSqlite -CsvPath .\data\users.csv -Database .\myapp.db -TableName users -SchemaMode AppendOnly
```

### 4. Generate Dynamic Models
```powershell
# Update the catalog and export model types
$types = Export-DynamicModelsFromCatalog -Database .\myapp.db

# Create PowerShell classes from the models
Set-DynamicORMClass
```

### 5. Query Your Data
```powershell
# Create a query builder instance
$query = New-DbQuery -Database .\myapp.db -From 'assets'

# Add conditions and execute
$results = $query.Where('status = @status', @{status='active'}).Run()

# Or use joins for related data
$query = New-DbQuery -Database .\myapp.db -From 'assets'
$results = $query.Join('users', 'assets.owner_id = users.id').Select(@('assets.*', 'users.name as owner_name')).Run()
```

### 6. Work with Dynamic Models
```powershell
# Create a new record
$asset = New-DynamicModel -Type 'Asset' -Properties @{
    name = 'Server-01'
    status = 'active'
    owner_id = 1
}
$asset.Save()

# Find and update existing records
$asset = [Asset]::Find(1)
$asset.status = 'maintenance'
$asset.Save()

# Delete a record
$asset.Delete()
```