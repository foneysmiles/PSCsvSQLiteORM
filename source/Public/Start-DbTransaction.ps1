function Start-DbTransaction {
    param([Parameter(Mandatory)][string]$Database)
    $conn = Get-DbConnection -Database $Database
    if ($conn -and $conn.State -eq 'Open') { return $conn.BeginTransaction() }
    Ensure-ForeignKeysPragma -Database $Database
    Invoke-DbQuery -Database $Database -Query 'BEGIN' -NonQuery | Out-Null; return $null
}