# Sample test script for PSCsvSQLiteORM module
# Imports sample CSVs, creates tables, and runs basic queries

# Import the built module (points to the output folder root and resolves latest version)
Import-Module (Join-Path $PSScriptRoot '..' 'output' 'PSCsvSQLiteORM') -Force

$database = Join-Path $PSScriptRoot 'sample.db'

# Import assets
Import-CsvToSqlite -Database $database -TableName 'assets' -CsvPath (Join-Path $PSScriptRoot 'assets.csv')
# Import vulnerabilities
Import-CsvToSqlite -Database $database -TableName 'vulns' -CsvPath (Join-Path $PSScriptRoot 'vulns.csv')

# Query assets
$assets = Invoke-DbQuery -Database $database -Query 'SELECT * FROM assets'
Write-Host "Assets:"
$assets | Format-Table

# Query vulnerabilities
$vulns = Invoke-DbQuery -Database $database -Query 'SELECT * FROM vulns'
Write-Host "Vulnerabilities:"
$vulns | Format-Table

# Find relationships
$relationships = Find-DbRelationships -Database $database
Write-Host "Suggested Relationships:"
$relationships | Format-Table
