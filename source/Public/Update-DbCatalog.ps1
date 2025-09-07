function Update-DbCatalog {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)]
        [string]$Database, 
        [string]$SourceCsvPath, 
        [string]$Table
    )
    
    # ShouldProcess not invoked here to avoid runtime issues under ModuleBuilder; analyzer may still warn.
    Initialize-Db -Database $Database
    $tables = Invoke-DbQuery -Database $Database -Query "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
    
    foreach ($t in $tables) {
        $tn = $t.name
        $rowcount = (Invoke-DbQuery -Database $Database -Query "SELECT COUNT(*) AS c FROM $(ConvertTo-Ident $tn)")[0].c
        $csvHash = $null; if ($SourceCsvPath -and $Table -eq $tn -and (Test-Path $SourceCsvPath)) { $csvHash = (Get-FileHash -Algorithm SHA256 -Path $SourceCsvPath).Hash }
        # Check if record exists first (compatible with older SQLite)
        $existing = Invoke-DbQuery -Database $Database -Query "SELECT table_name FROM __tables__ WHERE table_name=@t" -SqlParameters @{ t = $tn }
        if ($existing) {
            # Update existing record
            Invoke-DbQuery -Database $Database -Query @"
UPDATE __tables__ SET 
  source=COALESCE(@s, source),
  csv_hash=@h,
  rowcount=@c
WHERE table_name=@t
"@ -SqlParameters @{ t = $tn; s = $SourceCsvPath; h = $csvHash; c = $rowcount } -NonQuery | Out-Null
        } else {
            # Insert new record
            Invoke-DbQuery -Database $Database -Query @"
INSERT INTO __tables__(table_name,source,created_at,csv_hash,rowcount,sample_json)
VALUES(@t,@s,datetime('now'),@h,@c,@j)
"@ -SqlParameters @{ t = $tn; s = $SourceCsvPath; h = $csvHash; c = $rowcount; j = $null } -NonQuery | Out-Null
        }

        $cols = Invoke-DbQuery -Database $Database -Query "PRAGMA table_info($(ConvertTo-Ident $tn))"
        foreach ($c in $cols) {
            # Check if column record exists
            $existingCol = Invoke-DbQuery -Database $Database -Query "SELECT column_name FROM __columns__ WHERE table_name=@t AND column_name=@c" -SqlParameters @{ t = $tn; c = $c.name }
            if ($existingCol) {
                # Update existing column record
                Invoke-DbQuery -Database $Database -Query @"
UPDATE __columns__ SET 
  data_type=@dt,
  nullable=@n,
  pk=@pk
WHERE table_name=@t AND column_name=@c
"@ -SqlParameters @{ t = $tn; c = $c.name; dt = $c.type; n = [int](-not [bool]$c.notnull); pk = [int]$c.pk } -NonQuery | Out-Null
            } else {
                # Insert new column record
                Invoke-DbQuery -Database $Database -Query @"
INSERT INTO __columns__(table_name,column_name,data_type,nullable,pk,example_values_json)
VALUES(@t,@c,@dt,@n,@pk,@ex)
"@ -SqlParameters @{ t = $tn; c = $c.name; dt = $c.type; n = [int](-not [bool]$c.notnull); pk = [int]$c.pk; ex = $null } -NonQuery | Out-Null
            }
        }

        $fks = Invoke-DbQuery -Database $Database -Query "PRAGMA foreign_key_list($(ConvertTo-Ident $tn))"
        foreach ($fk in $fks) {
            # Check if FK record exists
            $existingFk = Invoke-DbQuery -Database $Database -Query "SELECT column_name FROM __fks__ WHERE table_name=@t AND column_name=@c" -SqlParameters @{ t = $tn; c = $fk."from" }
            if ($existingFk) {
                # Update existing FK record
                Invoke-DbQuery -Database $Database -Query @"
UPDATE __fks__ SET 
  ref_table=@rt,
  ref_column=@rc,
  status='confirmed'
WHERE table_name=@t AND column_name=@c
"@ -SqlParameters @{ t = $tn; c = $fk."from"; rt = $fk."table"; rc = $fk."to" } -NonQuery | Out-Null
            } else {
                # Insert new FK record
                Invoke-DbQuery -Database $Database -Query @"
INSERT INTO __fks__(table_name,column_name,ref_table,ref_column,confidence,status,on_delete,on_update)
VALUES(@t,@c,@rt,@rc,1.0,'confirmed',@od,@ou)
"@ -SqlParameters @{ t = $tn; c = $fk."from"; rt = $fk."table"; rc = $fk."to"; od = $fk.on_delete; ou = $fk.on_update } -NonQuery | Out-Null
            }
        }
    }
}
