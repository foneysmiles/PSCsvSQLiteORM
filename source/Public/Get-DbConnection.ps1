function Get-DbConnection {
    param([Parameter(Mandatory)][string]$Database)
    if ($script:DbPool.ContainsKey($Database)) { return $script:DbPool[$Database] }
    try { Add-Type -AssemblyName System.Data.SQLite -ErrorAction Stop | Out-Null }
    catch { Write-DbLog WARN "System.Data.SQLite not available; using PSSQLite only."; $script:DbPool[$Database] = $null; return $null }
    $conn = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$Database;Version=3;")
    $conn.Open()
    $cmd = $conn.CreateCommand(); $cmd.CommandText = 'PRAGMA foreign_keys = ON;'; [void]$cmd.ExecuteNonQuery(); $cmd.Dispose()
    $script:DbPool[$Database] = $conn
    return $conn
}
