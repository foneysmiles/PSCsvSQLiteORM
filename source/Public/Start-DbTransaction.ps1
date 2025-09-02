function Start-DbTransaction {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param([Parameter(Mandatory)][string]$Database)
    $conn = Get-DbConnection -Database $Database
    if ($conn -and $conn.State -eq 'Open') {
        $proceed = $true
        if ($PSCmdlet) { $proceed = $PSCmdlet.ShouldProcess($Database, 'Begin SQLite transaction') }
        if ($proceed) { return $conn.BeginTransaction() } else { return $null }
    }
    # Fallback path (PSSQLite): no persistent transaction support is guaranteed
    Enable-ForeignKeysPragma -Database $Database
    return $null
}
