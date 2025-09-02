# This script uses ModuleBuilder to build the PSCsvSQLiteORM module from your source files.
# It assumes your module manifest is PSCsvSQLiteORM.psd1 and your source files are in 'source/'.
# The output module will be placed in 'output/'.

$ModuleName = 'PSCsvSQLiteORM'
$SourcePath = Join-Path $PSScriptRoot 'source'
$OutputPath = Join-Path $PSScriptRoot 'output'
$ManifestPath = Join-Path $SourcePath 'PSCsvSQLiteORM.psd1'

# Ensure output directory exists
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath | Out-Null
}

# Build the module
Import-Module ModuleBuilder
Build-Module -SourcePath .\source -OutputDirectory 'C:\Users\Jaga\Documents\Scripts\PSCsvSqliteORM\PSCsvSQLiteORM\output' -Verbose -Version 3.01

# Import the built module for testing
$BuiltModulePath = Join-Path $OutputPath $ModuleName
Import-Module $BuiltModulePath -Force -Verbose

# Run Pester tests if available
$TestPath = Join-Path $PSScriptRoot 'Tests'
if (Test-Path $TestPath) {
    Write-Host "Running Pester tests..."
    Invoke-Pester -Path $TestPath
} else {
    Write-Host "No Tests folder found. Please add Pester tests for automated verification."
}
