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

# Normalize API key (avoid stray whitespace)
$NuGetApiKey = $NuGetApiKey.Trim()
if ([string]::IsNullOrWhiteSpace($NuGetApiKey)) { throw "NuGetApiKey is empty after trim." }
Write-Host ("Using API key: {0}**** (len={1})" -f $NuGetApiKey.Substring(0,[Math]::Min(6,$NuGetApiKey.Length)), $NuGetApiKey.Length)

# Run tests first
if (Test-Path (Join-Path $root 'Tests')) {
    Write-Host 'Running Pester tests...'
    $results = Invoke-Pester -Path (Join-Path $root 'Tests') -PassThru
    if ($results.FailedCount -gt 0) { throw "Tests failed: $($results.FailedCount)" }
}

# Resolve publish path as the module base containing version folders
if (-not (Test-Path $moduleBase)) { throw "Built module folder not found: $moduleBase. Run build-and-test.ps1 first." }

$publishParams = @{ Path = $moduleBase; NuGetApiKey = $NuGetApiKey; Repository = $Repository; Verbose = $true }
if ($WhatIf) { $publishParams['WhatIf'] = $true }
try {
    Publish-Module @publishParams
    Write-Host "Published $moduleName v$version to $Repository (WhatIf=$($WhatIf.IsPresent))"
}
catch {
    $msg = $_.Exception.Message
    if ($msg -match '403.*API key is invalid|Forbidden') {
        Write-Error "Failed to publish: 403 Forbidden. Your API key is invalid/expired or lacks permission. Regenerate a PowerShell Gallery API key with 'Push new packages and package updates' for $moduleName, then retry."
    }
    else {
        Write-Error "Failed to publish module: $msg"
    }
    throw
}
