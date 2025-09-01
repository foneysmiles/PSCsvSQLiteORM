function Start-DbTransaction {
    param([Parameter(Mandatory)][string]$Database)
    $conn = Get-DbConnection -Database $Database
    if ($conn -and $conn.State -eq 'Open') { return $conn.BeginTransaction() }
    # Fallback path (PSSQLite): no persistent transaction support is guaranteed
    Enable-ForeignKeysPragma -Database $Database
    return $null
}
