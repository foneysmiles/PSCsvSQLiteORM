# PowerShell SQLite ORM Framework - Complete Usage Guide

# CSV import with automatic schema inference
# Dynamic model generation with Active Record pattern
# Relationship management (has_many, belongs_to)
# Query builder with automatic joins
# Bulk operations and upserts
# Migration system
# Database catalog and metadata tracking


# Import Module
Import-Module PSCsvSQLiteORM -Force 

# Configure ORM variables (equivalent of a settings script)
Initialize-ORMVars -LogLevel DEBUG -LogPath 'C:\Users\Jaga\Documents\Scripts\ORM\database_2.log'

# Define your database path
$db = 'C:\Users\Jaga\Documents\Scripts\ORM\test_4.db'
$csvVulns = 'C:\Users\Jaga\Downloads\qualys_vulnerability_data.csv'
$csvAssets = 'C:\Users\Jaga\Downloads\qualys_asset_details.csv'

### 2. Import CSV Data to Create Tables
# Import vulnerability data
$vulnsColumns = Import-CsvToSqlite `
    -CsvPath $csvVulns `
    -Database $db `
    -TableName 'vulns' `
    -SchemaMode Relaxed `
    -BatchSize 1000

# Import asset data
$assetColumns = Import-CsvToSqlite `
    -CsvPath $csvAssets `
    -Database $db `
    -TableName 'assets' `
    -SchemaMode Relaxed

### Schema Modes:
# Strict: Fails if CSV has columns not in existing table
# Relaxed: Automatically adds missing columns (default)
# AppendOnly: Only inserts, no schema changes

## Relationship Management

### 3. Define and Confirm Relationships
# Update database catalog
Update-DbCatalog -Database $db -SourceCsvPath $csvAssets -Table 'assets'

# Auto-suggest relationships based on column names
Find-DbRelationships -Database $db

# Confirm specific foreign key relationships
Confirm-DbForeignKey `
    -Database $db `
    -From 'vulns' `
    -Column 'hostname' `
    -To 'assets' `
    -RefColumn 'hostname' `
    -OnDelete CASCADE


## Dynamic Model Generation

### 4. Generate and Load Dynamic Models
# Generate dynamic classes for all tables and load them
$modelTypes = Export-DynamicModelsFromCatalog -Database $db
Set-DynamicORMClass

# Now you can use your dynamic models
$assetModel = [DynamicAssets]::new($db)
$vulnModel = [DynamicVulns]::new($db)

## CRUD Operations

### 5. Creating New Records

#### Single Record Creation
# Create new asset
$newAsset = [DynamicAssets]::new($db)
$newAsset.hostname('server-001.domain.com')
$newAsset.ip_address('192.168.1.100')
$newAsset.asset_type('Server')
$newAsset.operating_system('Windows Server 2019')
$newAsset.last_scanned('2025-10-02 08:05:00')
$newAsset.Save()

# The ID is automatically set after save
Write-Host "New asset created with ID: $($newAsset.Id)"

# Create vulnerability record
$newVuln = [DynamicVulns]::new($db)
$newVuln.hostname('server-001.domain.com')
$newVuln.cve_id('CVE-2023-12345')
$newVuln.vulnerability_title('Sample Vulnerability')
$newVuln.severity('High')
$newVuln.Save()

#### Bulk Record Creation
# Prepare bulk data
$bulkAssets = @(
    @{ hostname = 'web-01.domain.com'; ip_address = '10.0.1.50'; asset_type = 'Server' },
    @{ hostname = 'web-02.domain.com'; ip_address = '10.0.1.51'; asset_type = 'Server' },
    @{ hostname = 'db-01.domain.com'; ip_address = '10.0.2.10'; asset_type = 'Database' }
)

# Bulk insert using model
$assetModel = [DynamicAssets]::new($db)
$assetModel.InsertMany($bulkAssets)

### 6. Reading/Querying Records

#### Basic Queries
# Get all records
$allAssets = $assetModel.All()

# Get first record
$firstAsset = $assetModel.First('hostname ASC')

# Servers scanned in last 5 days
$q = New-DbQuery -Database $db -From 'assets'
$q = $q.Where('asset_type = @t', @{ t = 'Server' })
$q = $q.Where('last_scanned >= @d', @{ d = (Get-Date).AddDays(-5).ToString('yyyy-MM-ddTHH:mm:ssZ') })
$q = $q.Select(@('asset_id','hostname','last_scanned'))
$q.OrderBy = 'last_scanned DESC'
$rows = $q.Run()
$rows | Format-Table 

# Linux-based assets
$q = New-DbQuery -Database $db -From 'assets'
$q = $q.Where('(operating_system LIKE @os OR tags LIKE @tag)', @{ os = '%Linux%'; tag = '%linux%' })
$q = $q.Select(@('asset_id','hostname','operating_system','tags'))
$rows = $q.Run()
$rows | Format-Table 

# Private subnets
$q = New-DbQuery -Database $db -From 'assets'
$q = $q.Where('(ip_address LIKE @a OR ip_address LIKE @b OR ip_address LIKE @c)', @{
  a = '10.%'; b = '172.16.%'; c = '192.168.%'
})
$q = $q.Select(@('asset_id','hostname','ip_address'))
$q.OrderBy = 'ip_address ASC'
$rows = $q.Run()
$rows | Format-Table 

# Inner join to show all vulnerabilities with asset type
$q = New-DbQuery -Database $db -From 'vulns'
$q = $q.Join('assets', 'vulns.hostname = assets.hostname', 'Inner')
$q = $q.Select(@(
    'vulns.vuln_id',
    'vulns.cve_id',
    'assets.hostname',
    'vulns.vulnerability_title',
    'vulns.severity',
    'assets.asset_type'
))
$q.OrderBy = 'assets.hostname ASC'
$rows = $q.Run()
$rows | Format-Table 

### 7. Updating Records

#### Single Record Updates
# Find and update a record
$asset = $assetModel.where('asset_id = @id', @{ id = 1002354 })
if ($asset) {
    $asset.operating_system('Ubuntu 22.04 LTS')
    $asset.last_scanned((Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ'))
    $asset.Save()
}

# Update with validation
$asset.AddValidator('hostname', 'Required', $null)
$asset.AddValidator('ip_address', 'Regex', '^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$')
try {
    $asset.Save()
} catch {
    Write-Host "Validation failed: $_"
}

#### Bulk Updates Using Raw SQL
# Update multiple records with custom SQL
$assetModel.Raw(
    "UPDATE assets SET last_scanned = @scan_time WHERE asset_type = @type",
    @{ scan_time = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ'); type = 'Server' }
)

# Mass update using transaction
$tx = Start-DbTransaction -Database $db
try {
    foreach ($hostname in @('web-01', 'web-02', 'db-01')) {
        Invoke-DbQuery -Database $db -Query "UPDATE assets SET tags = @tags WHERE hostname LIKE @host" -SqlParameters @{ tags = 'production'; host = "$hostname%" } -NonQuery -Transaction $tx
    }
    Commit-DbTransaction -Database $db -Transaction $tx
} catch {
    Undo-DbTransaction -Database $db -Transaction $tx
    throw
}

### 8. Upsert Operations (Insert or Update)

#### Single Record Upsert
# Upsert based on hostname (requires unique index)
$assetData = @{
    hostname = 'server-001.domain.com'
    ip_address = '192.168.1.100'
    asset_type = 'Server'
    operating_system = 'Windows Server 2022'
    last_scanned = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
}

$assetModel.InsertOnConflict(
    $assetData,
    @('hostname'),  # Key columns for conflict detection
    @{              # Columns to update on conflict
        ip_address = '@ip_address'
        operating_system = '@operating_system'
        last_scanned = '@last_scanned'
    }
)

#### Bulk Upserts
# Prepare bulk upsert data
$bulkUpsertData = @(
    @{ hostname = 'web-01.domain.com'; ip_address = '10.0.1.50'; asset_type = 'Server'; status = 'Active' },
    @{ hostname = 'web-02.domain.com'; ip_address = '10.0.1.51'; asset_type = 'Server'; status = 'Maintenance' },
    @{ hostname = 'db-01.domain.com'; ip_address = '10.0.2.10'; asset_type = 'Database'; status = 'Active' }
)

# Bulk upsert
$assetModel.BulkUpsert($bulkUpsertData, @('hostname'))

### 9. Deleting Records

#### Single Record Deletion
# Delete by ID
$asset = $assetModel.FindById(12)
if ($asset) {
    $asset.Delete()
}

# Delete with callbacks
$asset.On('BeforeDelete', {
    param($record)
    Write-Host "About to delete asset: $($record.hostname())"
})
$asset.On('AfterDelete', {
    param($record)
    Write-Host "Deleted asset successfully"
})
$asset.Delete()

#### Bulk Deletion
# Delete multiple records using raw SQL
$vulnModel.Raw(
    "DELETE FROM vulns WHERE severity = @sev AND last_detected < @date",
    @{ sev = 'Low'; date = (Get-Date).AddDays(-90).ToString('yyyy-MM-dd') }
)

# Delete with cascading (if foreign keys are set up)
Invoke-DbQuery -Database $db -Query "DELETE FROM assets WHERE asset_type = @type" -SqlParameters @{ type = 'Decommissioned' } -NonQuery

## Advanced Querying with Query Builder

### 10. Complex Joins and Queries
# Join vulnerabilities with assets
$query = New-DbQuery -Database $db -From 'vulns'
$query = $query.Join('assets', 'vulns.hostname = assets.hostname', 'Inner')
$query = $query.Select(@(
    'vulns.vuln_id',
    'vulns.cve_id', 
    'assets.hostname',
    'vulns.vulnerability_title',
    'vulns.severity',
    'assets.asset_type',
    'assets.operating_system'
))
$query = $query.Where('vulns.severity IN (@high, @critical)', @{ high = 'High'; critical = 'Critical' })
$query = $query.OrderBy('assets.hostname ASC, vulns.severity DESC')
$results = $query.Run()

# Auto-join based on relationships
$autoJoinQuery = New-DbQuery -Database $db -From 'vulns'
$autoJoinQuery = $autoJoinQuery.Join('assets', 'Auto')  # Uses relationship metadata
$autoJoinQuery = $autoJoinQuery.Where('assets.asset_type = @type', @{ type = 'Server' })
$serverVulns = $autoJoinQuery.Run()

# Pagination
$pagedQuery = New-DbQuery -Database $db -From 'assets'
$pagedQuery = $pagedQuery.OrderBy('hostname ASC')
$pagedQuery = $pagedQuery.Limit(10).Offset(20)  # Get records 21-30
$page3Assets = $pagedQuery.Run()

## Working with Relationships

### 11. Using Has Many and Belongs To
# Set up relationships in models (done automatically by Export-DynamicModelsFromCatalog)
# But you can also define them manually:

# Define relationships manually if needed
$assetModel.HasMany('vulns', 'hostname')
$vulnModel.BelongsTo('assets', 'hostname')

# Use relationships
$asset = $assetModel.FindById(123)
$vulnerabilities = $asset.GetHasMany('vulns')
Write-Host "Asset $($asset.hostname()) has $($vulnerabilities.Count) vulnerabilities"

foreach ($vuln in $vulnerabilities) {
    Write-Host "  - $($vuln.vulnerability_title()) ($($vuln.severity()))"
}

# Get parent asset from vulnerability
$vuln = $vulnModel.FindById(456)
$parentAsset = $vuln.GetBelongsTo('assets')
if ($parentAsset) {
    Write-Host "Vulnerability affects: $($parentAsset.hostname())"
}

## Database Migrations

### 12. Managing Schema Changes
# Add a migration
Add-DbMigration -Database $db -Version '20231201_add_risk_score' -Up {
    param($database)
    Invoke-DbQuery -Database $database -Query "ALTER TABLE vulns ADD COLUMN risk_score INTEGER DEFAULT 0" -NonQuery
    Invoke-DbQuery -Database $database -Query "CREATE INDEX idx_vulns_risk_score ON vulns(risk_score)" -NonQuery
} -Down {
    param($database)
    # Note: SQLite doesn't support DROP COLUMN easily, so this is simplified
    Invoke-DbQuery -Database $database -Query "DROP INDEX IF EXISTS idx_vulns_risk_score" -NonQuery
}

# Check applied migrations
$appliedMigrations = Get-AppliedMigrations -Database $db
Write-Host "Applied migrations: $($appliedMigrations -join ', ')"

## Data Validation

### 13. Adding Validation Rules
# Add validators to models
$assetModel.AddValidator('hostname', 'Required', $null)
$assetModel.AddValidator('hostname', 'Regex', '^[a-zA-Z0-9.-]+$')
$assetModel.AddValidator('ip_address', 'Custom', {
    param($value)
    return $value -match '^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$'
})

# Validation is automatically checked on Save()
try {
    $invalidAsset = [DynamicAssets]::new($db)
    $invalidAsset.hostname('')  # Will fail Required validation
    $invalidAsset.Save()
} catch {
    Write-Host "Validation error: $_"
}

## Cleanup and Best Practices

### 14. Cleanup and Connection Management
# Always close connections when done
Close-DbConnections

# Clean up temporary class files (optional)
foreach ($script in $global:DynamicClassScripts) {
    if (Test-Path $script.ModelPath) {
        Remove-Item $script.ModelPath -ErrorAction SilentlyContinue
    }
}
$global:DynamicClassScripts = @()

## Complete Example Workflow
# 1. Setup
Set-DbLogging -Level debug -Path 'C:\Users\Jaga\Documents\Scripts\ORM\database_5.log'
$db = 'C:\Users\Jaga\Documents\Scripts\ORM\test_5.db'
$csvVulns = 'C:\Users\Jaga\Downloads\qualys_vulnerability_data.csv'
$csvAssets = 'C:\Users\Jaga\Downloads\qualys_asset_details.csv'

# 2. Import data
Import-CsvToSqlite -CsvPath $csvAssets -Database $db -TableName 'assets'
Import-CsvToSqlite -CsvPath $csvVulns -Database $db -TableName 'vulns'

# 3. Set up relationships
Update-DbCatalog -Database $db
Find-DbRelationships -Database $db
Confirm-DbForeignKey -Database $db -From 'vulns' -Column 'hostname' -To 'assets'

# 4. Generate models
Export-DynamicModelsFromCatalog -Database $db
foreach ($script in $global:DynamicClassScripts) {
    Invoke-Expression (Get-Content $script.ModelPath -Raw)
}

# 5. Work with data
$assetModel = [DynamicAssets]::new($db)
$criticalServers = $assetModel.Where('asset_type = @type AND criticality = @crit', 
    @{ type = 'Server'; crit = 'High' })

foreach ($server in $criticalServers) {
    $vulns = $server.GetHasMany('vulns')
    $highVulns = $vulns | Where-Object { $_.severity() -in @('High', 'Critical') }
    Write-Host "$($server.hostname()): $($highVulns.Count) high/critical vulnerabilities"
}

# 6. Cleanup
Close-DbConnections

# Clean up temporary class files (optional)
foreach ($script in $global:DynamicClassScripts) {
    if (Test-Path $script.ModelPath) {
        Remove-Item $script.ModelPath -ErrorAction SilentlyContinue
    }
}
$global:DynamicClassScripts = @()
