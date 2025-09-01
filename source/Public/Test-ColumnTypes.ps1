function Test-ColumnTypes {
    param ([Parameter(Mandatory)][array]$Csv, [Parameter(Mandatory)][string[]]$Headers)
    $columnTypes = @{}
    foreach ($header in $Headers) {
        if ($header -eq "id") { $columnTypes[$header] = "INTEGER PRIMARY KEY AUTOINCREMENT"; continue }
        $isInteger = $true; $isReal = $true
        foreach ($row in $Csv) {
            $value = $row.$header
            if ($null -eq $value -or $value -eq "") { continue }
            if ($isInteger -and $value -notmatch '^-?\d+$') { $isInteger = $false }
            if ($isReal -and $value -notmatch '^-?\d+(\.\d+)?$') { $isReal = $false }
        }
        if ($isInteger) { $columnTypes[$header] = "INTEGER" }
        elseif ($isReal) { $columnTypes[$header] = "REAL" }
        else { $columnTypes[$header] = "TEXT" }
    }
    return $columnTypes
}

