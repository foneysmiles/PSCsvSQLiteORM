# Functional tests for PSCsvSQLiteORM

Import-Module (Join-Path $PSScriptRoot '..' 'output' 'PSCsvSQLiteORM') -Force

Describe 'Initialize-ORMVars settings script' {
    It 'Applies settings from a SettingsPath file' {
        $tmpDir = Join-Path $PSScriptRoot 'tmp'
        if (-not (Test-Path -LiteralPath $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir | Out-Null }
        $logFile = Join-Path $tmpDir ("orm_{0}.log" -f ([guid]::NewGuid().ToString('N')))
        $settingsPath = Join-Path $env:TEMP ("orm_settings_{0}.ps1" -f ([guid]::NewGuid().ToString('N')))
        "@{ LogLevel = 'DEBUG'; LogPath = '$logFile' }" | Set-Content -LiteralPath $settingsPath -Encoding UTF8

        Initialize-ORMVars -SettingsPath $settingsPath
        Write-DbLog INFO 'hello from test'

        Test-Path -LiteralPath $logFile | Should -BeTrue
        (Get-Content -LiteralPath $logFile -Raw) | Should -Match 'hello from test'
    }
}

Describe 'Import-CsvToSqlite AppendOnly mode' {
    $tmpDir = Join-Path $PSScriptRoot 'tmp'
    if (-not (Test-Path -LiteralPath $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir | Out-Null }
    $db = Join-Path $tmpDir ("orm_func_{0}.db" -f ([guid]::NewGuid().ToString('N')))
    It 'Throws if table does not exist in AppendOnly' {
        { Import-CsvToSqlite -CsvPath (Join-Path $PSScriptRoot 'assets.csv') -Database $db -TableName 'new_assets' -SchemaMode AppendOnly } | Should -Throw
    }
}

Describe 'Find-DbRelationships returns suggestions' {
    It 'Suggests relationships based on *_id' {
        $tmpDir = Join-Path $PSScriptRoot 'tmp'
        if (-not (Test-Path -LiteralPath $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir | Out-Null }
        $db = Join-Path $tmpDir ("orm_rel_{0}.db" -f ([guid]::NewGuid().ToString('N')))

        # Import sample csvs (Relaxed schema)
        Import-CsvToSqlite -CsvPath (Join-Path $PSScriptRoot 'assets.csv') -Database $db -TableName 'assets' -SchemaMode Relaxed | Out-Null
        Import-CsvToSqlite -CsvPath (Join-Path $PSScriptRoot 'vulns.csv') -Database $db -TableName 'vulns' -SchemaMode Relaxed | Out-Null

        $sugs = Find-DbRelationships -Database $db
        $sugs | Should -Not -BeNullOrEmpty
        ($sugs | Get-Member -Type NoteProperty | Select-Object -ExpandProperty Name) | Should -Contain 'table_name'
        ($sugs | Get-Member -Type NoteProperty | Select-Object -ExpandProperty Name) | Should -Contain 'column_name'
        ($sugs | Get-Member -Type NoteProperty | Select-Object -ExpandProperty Name) | Should -Contain 'ref_table'
        ($sugs | Get-Member -Type NoteProperty | Select-Object -ExpandProperty Name) | Should -Contain 'ref_column'
    }
}
