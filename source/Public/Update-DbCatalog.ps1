function Update-DbCatalog {
    param(
        [Parameter(Mandatory)]
        [string]$Database, 
        [string]$SourceCsvPath, 
        [string]$Table
    )
    
    Initialize-Db -Database $Database
    $tables = Invoke-DbQuery -Database $Database -Query "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
    
    foreach ($t in $tables) {
        $tn = $t.name
        $rowcount = (Invoke-DbQuery -Database $Database -Query "SELECT COUNT(*) AS c FROM $(ConvertTo-Ident $tn)")[0].c
        $csvHash = $null; if ($SourceCsvPath -and $Table -eq $tn -and (Test-Path $SourceCsvPath)) { $csvHash = (Get-FileHash -Algorithm SHA256 -Path $SourceCsvPath).Hash }
        Invoke-DbQuery -Database $Database -Query @"
INSERT INTO __tables__(table_name,source,created_at,csv_hash,rowcount,sample_json)
VALUES(@t,@s,COALESCE((SELECT created_at FROM __tables__ WHERE table_name=@t),(datetime('now'))),@h,@c,@j)
ON CONFLICT(table_name) DO UPDATE SET
  source=COALESCE(excluded.source,__tables__.source),
  csv_hash=excluded.csv_hash,
  rowcount=excluded.rowcount
"@ -SqlParameters @{ t = $tn; s = $SourceCsvPath; h = $csvHash; c = $rowcount; j = $null } -NonQuery | Out-Null

        $cols = Invoke-DbQuery -Database $Database -Query "PRAGMA table_info($(ConvertTo-Ident $tn))"
        foreach ($c in $cols) {
            Invoke-DbQuery -Database $Database -Query @"
INSERT INTO __columns__(table_name,column_name,data_type,nullable,pk,example_values_json)
VALUES(@t,@c,@dt,@n,@pk,@ex)
ON CONFLICT(table_name,column_name) DO UPDATE SET data_type=excluded.data_type, nullable=excluded.nullable, pk=excluded.pk
"@ -SqlParameters @{ t = $tn; c = $c.name; dt = $c.type; n = [int](-not [bool]$c.notnull); pk = [int]$c.pk; ex = $null } -NonQuery | Out-Null
        }

        $fks = Invoke-DbQuery -Database $Database -Query "PRAGMA foreign_key_list($(ConvertTo-Ident $tn))"
        foreach ($fk in $fks) {
            Invoke-DbQuery -Database $Database -Query @"
INSERT INTO __fks__(table_name,column_name,ref_table,ref_column,confidence,status,on_delete,on_update)
VALUES(@t,@c,@rt,@rc,1.0,'confirmed',@od,@ou)
ON CONFLICT(table_name,column_name) DO UPDATE SET ref_table=excluded.ref_table, ref_column=excluded.ref_column, status='confirmed'
"@ -SqlParameters @{ t = $tn; c = $fk."from"; rt = $fk."table"; rc = $fk."to"; od = $fk.on_delete; ou = $fk.on_update } -NonQuery | Out-Null
        }
    }
}
