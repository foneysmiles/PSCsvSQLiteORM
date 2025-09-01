function Enable-UpsertSupported {
    param([Parameter(Mandatory)][string]$Database)
    $v = Invoke-DbQuery -Database $Database -Query "SELECT sqlite_version() AS v;"
    $ver = $v[0].v
    $parts = $ver -split '\.'
    $major = [int]$parts[0]; $minor = [int]$parts[1]; $patch = [int]$parts[2]
    # Require 3.24.0+
    if ($major -lt 3 -or ($major -eq 3 -and ($minor -lt 24))) {
        throw "SQLite $ver does not support INSERT ... ON CONFLICT DO UPDATE (requires 3.24+)."
    }
}

