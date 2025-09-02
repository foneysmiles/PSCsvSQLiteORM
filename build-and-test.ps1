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
Import-Module ModuleBuilder -ErrorAction Stop

# Derive version from source manifest to keep things consistent
$manifestInfo = Test-ModuleManifest -Path $ManifestPath
$version = $manifestInfo.Version.ToString()
Write-Host "Building $ModuleName version $version to $OutputPath"

Build-Module -SourcePath $SourcePath -OutputDirectory $OutputPath -Verbose -Version $version

# Copy ancillary docs/examples into the built module folder
$builtBase = Join-Path $OutputPath $ModuleName
$builtVersionPath = Join-Path $builtBase $version
$docsSrc = Join-Path $PSScriptRoot 'docs'
if (Test-Path $docsSrc) {
    Copy-Item -Recurse -Force $docsSrc (Join-Path $builtVersionPath 'docs')
}
$examplesSrc = Join-Path $SourcePath 'Examples'
if (Test-Path $examplesSrc) {
    Copy-Item -Recurse -Force $examplesSrc (Join-Path $builtVersionPath 'Examples')
}

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
