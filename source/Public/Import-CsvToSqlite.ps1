function Import-CsvToSqlite {
    param (
        [Parameter(Mandatory)][string]$CsvPath,
        [Parameter(Mandatory)][string]$Database,
        [Parameter(Mandatory)][string]$TableName,
        [string[]]$ForeignKeys = @(),
        [string[]]$NullTokens = @('', 'NULL', 'N/A', 'NaN'),
        [hashtable]$BoolTokens = @{ true = @('true', '1', 'yes', 'y'); false = @('false', '0', 'no', 'n') },
        [ValidateSet('Strict', 'Relaxed', 'AppendOnly')][string]$SchemaMode = 'Relaxed',
        [int]$BatchSize = 0  # 0 = all
    )
    $csv = Import-Csv -Path $CsvPath
    if (-not $csv) { throw "CSV file is empty or invalid." }
    
    # Normalize null/bool tokens
    foreach ($row in $csv) {
        foreach ($p in $row.PSObject.Properties.Name) {
            $val = $row.$p
            if ($NullTokens -contains $val) { $row.$p = $null; continue }
            if ($val -is [string]) {
                $lc = $val.ToLowerInvariant()
                if ($BoolTokens.true -contains $lc) { $row.$p = 1; continue }
                if ($BoolTokens.false -contains $lc) { $row.$p = 0; continue }
            }
        }
    }

    $headers = $csv[0].PSObject.Properties.Name
    if (-not $headers -or $headers.Count -eq 0) { throw "No columns in CSV." }

    $columnTypes = Infer-ColumnTypes -Csv $csv -Headers $headers
    foreach ($h in $headers) { if (-not $columnTypes[$h]) { $columnTypes[$h] = 'TEXT' } }

    $quotedCols = ($headers | ForEach-Object { "$(Quote-Ident $_) $($columnTypes[$_])" }) -join ", "
    if (-not [string]::IsNullOrWhiteSpace($quotedCols)) {
        $createQuery = "CREATE TABLE IF NOT EXISTS $(Quote-Ident $TableName) ($quotedCols)"
        Invoke-DbQuery -Database $Database -Query $createQuery -NonQuery | Out-Null
    }

    # Evolve schema
    $existing = Invoke-DbQuery -Database $Database -Query "PRAGMA table_info($(Quote-Ident $TableName))"
    $existingNames = $existing | ForEach-Object { $_.name }
    if ($SchemaMode -in @('Relaxed')) {
        foreach ($h in $headers) {
            if ($existingNames -notcontains $h) {
                $sql = "ALTER TABLE $(Quote-Ident $TableName) ADD COLUMN $(Quote-Ident $h) $($columnTypes[$h])"
                Invoke-DbQuery -Database $Database -Query $sql -NonQuery | Out-Null
            }
        }
    }
    elseif ($SchemaMode -eq 'Strict') {
        foreach ($h in $headers) { if ($existingNames -notcontains $h) { throw "Strict mode: missing column $h in $TableName" } }
    }

    # Insert data
    $tx = Start-DbTransaction -Database $Database
    try {
        $count = 0
        foreach ($row in $csv) {
            $keys = $row.PSObject.Properties.Name
            $columns = (($keys | ForEach-Object { Quote-Ident $_ })) -join ", "
            $placeholders = (($keys | ForEach-Object { "@$_" })) -join ", "
            $query = "INSERT INTO $(Quote-Ident $TableName) ($columns) VALUES ($placeholders)"
            $params = @{}
            foreach ($k in $keys) { $params[$k] = $row.$k }
            [void](Invoke-DbQuery -Database $Database -Query $query -SqlParameters $params -NonQuery -Transaction $tx)
            $count++
            if ($BatchSize -gt 0 -and ($count % $BatchSize) -eq 0) {
                $pct = [int](($count / [double]$csv.Count) * 100)
                Write-Progress -Activity "Importing $TableName" -Status "$count / $($csv.Count)" -PercentComplete $pct
            }
        }
        Commit-DbTransaction -Database $Database -Transaction $tx
    }
    catch { Rollback-DbTransaction -Database $Database -Transaction $tx; throw }

    Update-DbCatalog -Database $Database -SourceCsvPath $CsvPath -Table $TableName
    return $headers
}