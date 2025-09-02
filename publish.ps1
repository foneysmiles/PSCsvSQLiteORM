param(
    [Parameter(Mandatory)]
    [string]$NuGetApiKey,
    [string]$Repository = 'PSGallery',
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

$moduleName = 'PSCsvSQLiteORM'
$root = $PSScriptRoot
$sourceManifest = Join-Path $root 'source\PSCsvSQLiteORM.psd1'
$manifestInfo = Test-ModuleManifest -Path $sourceManifest
$version = $manifestInfo.Version.ToString()
$moduleBase = Join-Path (Join-Path $root 'output') $moduleName

Write-Host "Preparing to publish $moduleName v$version"

# Run tests first
if (Test-Path (Join-Path $root 'Tests')) {
    Write-Host 'Running Pester tests...'
    $results = Invoke-Pester -Path (Join-Path $root 'Tests') -PassThru
    if ($results.FailedCount -gt 0) { throw "Tests failed: $($results.FailedCount)" }
}

# Resolve publish path as the module base containing version folders
if (-not (Test-Path $moduleBase)) { throw "Built module folder not found: $moduleBase. Run build-and-test.ps1 first." }

$publishParams = @{ Path = $moduleBase; NuGetApiKey = $NuGetApiKey; Repository = $Repository }
if ($WhatIf) { $publishParams['WhatIf'] = $true }

Publish-Module @publishParams
Write-Host "Published $moduleName v$version to $Repository (WhatIf=$($WhatIf.IsPresent))"

