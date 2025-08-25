function Get-TableColumns {
    param([Parameter(Mandatory)][string]$Database, [Parameter(Mandatory)][string]$TableName)
    $cols = Invoke-DbQuery -Database $Database -Query "PRAGMA table_info(""$TableName"")" | Sort-Object -Property cid
    return ($cols | ForEach-Object { $_.name })
}