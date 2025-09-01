#Region '.\Classes\DbJoinSpec.ps1' -1

class DbJoinSpec { [string]$Type; [string]$Table; [string]$On }
#EndRegion '.\Classes\DbJoinSpec.ps1' 2
#Region '.\Classes\DbQuery.ps1' -1

class DbQuery {
    [string]$Database; [string]$From
    [System.Collections.ArrayList]$Joins = [System.Collections.ArrayList]::new()
    [System.Collections.ArrayList]$Selects = [System.Collections.ArrayList]::new()
    [System.Collections.ArrayList]$Wheres = [System.Collections.ArrayList]::new()
    [hashtable]$Params = @{}; [string]$OrderBy; [int]$Limit = -1; [int]$Offset = -1

    DbQuery([string]$database, [string]$from) { $this.Database = $database; $this.From = $from }

    [DbQuery]Select([string[]]$Cols) { if ($Cols) { foreach ($c in $Cols) { [void]$this.Selects.Add($c) } }; return $this }
    [DbQuery]Where([string]$Clause, [hashtable]$Params) {
        if ($Clause) { [void]$this.Wheres.Add($Clause) }
        if ($Params) { foreach ($k in $Params.Keys) { if ($this.Params.ContainsKey($k)) { throw "Duplicate parameter key '$k' in DbQuery.Where()" }; $this.Params[$k] = $Params[$k] } }
        return $this
    }
    [DbQuery]OrderBy([string]$Expr) { $this.OrderBy = $Expr; return $this }
    [DbQuery]Limit([int]$n) { $this.Limit = $n; return $this }
    [DbQuery]Offset([int]$n) { $this.Offset = $n; return $this }

    hidden [string]GetBaseTable([string]$t) { if ($t -match '^\s*([^\s]+)') { return $Matches[1].Trim('"') } return $t }
    [DbQuery]Join([string]$Table, [string]$On, [string]$Type = 'Inner') {
        if ($Type -notin @('Inner', 'Left', 'Right', 'Full')) { throw "Invalid join type '$Type'." }
        $spec = [DbJoinSpec]::new(); $spec.Type = $Type; $spec.Table = $Table
        if ($On -eq 'Auto') {
            $baseA = $this.GetBaseTable($this.From); $baseB = $this.GetBaseTable($Table)
            $q = @"
SELECT * FROM __fks__
WHERE (table_name=@a AND ref_table=@b) OR (table_name=@b AND ref_table=@a)
ORDER BY status='confirmed' DESC, confidence DESC
LIMIT 1
"@
            $rel = Invoke-DbQuery -Database $this.Database -Query $q -SqlParameters @{ a = $baseA; b = $baseB }
            if ($rel -and $rel.Count -gt 0) {
                $r = $rel[0]
                if ($r.table_name -eq $baseB -and $r.ref_table -eq $baseA) { $spec.On = "$Table.`"$($r.column_name)`" = $($this.From).`"$($r.ref_column)`"" }
                else { $spec.On = "$($this.From).`"$($r.column_name)`" = $Table.`"$($r.ref_column)`"" }
            }
            else { throw "No relationship found between $baseA and $baseB for Auto join." }
        }
        else { $spec.On = $On }
        [void]$this.Joins.Add($spec); return $this
    }

    [object[]]Run() {
        $selectClause = if ($this.Selects.Count -gt 0) { ($this.Selects -join ', ') } else { '*' }
        $hasRightOrFull = $false
        foreach ($j in $this.Joins) { if ($j.Type -in @('Right','Full')) { $hasRightOrFull = $true } }

        if (-not $hasRightOrFull) {
            $sql = "SELECT $selectClause FROM $($this.From)"
            foreach ($j in $this.Joins) {
                $jt = switch ($j.Type) { 'Left' { 'LEFT JOIN' } default { 'INNER JOIN' } }
                $sql += " $jt $($j.Table) ON $($j.On)"
            }
            if ($this.Wheres.Count -gt 0) { $sql += " WHERE " + ($this.Wheres -join " AND ") }
            if ($this.OrderBy) { $sql += " ORDER BY $($this.OrderBy)" }
            if ($this.Limit -gt -1) { $sql += " LIMIT $($this.Limit)" }
            if ($this.Offset -gt -1) { $sql += " OFFSET $($this.Offset)" }
            return Invoke-DbQuery -Database $this.Database -Query $sql -SqlParameters $this.Params
        }
        else {
            if ($this.Joins.Count -ne 1) { throw "RIGHT/FULL join emulation currently supports a single join only." }
            $j = $this.Joins[0]
            if ($j.Type -eq 'Right') {
                # Emulate RIGHT JOIN by swapping tables into a LEFT JOIN
                $sql = "SELECT $selectClause FROM $($j.Table) LEFT JOIN $($this.From) ON $($j.On)"
            }
            elseif ($j.Type -eq 'Full') {
                # Emulate FULL OUTER JOIN via UNION of two LEFT JOINs
                $left = "SELECT $selectClause FROM $($this.From) LEFT JOIN $($j.Table) ON $($j.On)"
                $right = "SELECT $selectClause FROM $($j.Table) LEFT JOIN $($this.From) ON $($j.On)"
                $sql = "$left UNION $right"
            }
            else { throw "Unexpected join type for emulation: $($j.Type)" }

            if ($this.Wheres.Count -gt 0) { $sql = "$sql WHERE " + ($this.Wheres -join " AND ") }
            if ($this.OrderBy) { $sql += " ORDER BY $($this.OrderBy)" }
            if ($this.Limit -gt -1) { $sql += " LIMIT $($this.Limit)" }
            if ($this.Offset -gt -1) { $sql += " OFFSET $($this.Offset)" }
            return Invoke-DbQuery -Database $this.Database -Query $sql -SqlParameters $this.Params
        }
    }
}
#EndRegion '.\Classes\DbQuery.ps1' 84
#Region '.\Classes\DynamicActiveRecord.ps1' -1

class DynamicActiveRecord {
    hidden [string]$TableName
    hidden [string]$Database
    hidden [hashtable]$Attributes = @{}
    hidden [int]$Id
    hidden [string[]]$Columns
    hidden [hashtable]$Associations = @{}
    hidden [hashtable]$Validators = @{}
    hidden [hashtable]$Callbacks = @{
        BeforeSave = $null; AfterSave = $null; BeforeDelete = $null; AfterDelete = $null
    }
    hidden [string[]]$ExcludedProperties = @('RowState', 'RowError', 'HasErrors', 'Table', 'ItemArray')

    DynamicActiveRecord([string]$tableName, [string]$database, [string[]]$columns) {
        $this.TableName = $tableName; $this.Database = $database; $this.Columns = $columns; $this.Id = 0
    }

    [void]HasMany([string]$relatedTable, [string]$foreignKey) { $this.Associations["has_many_$relatedTable"] = @{ Type = "has_many"; Table = $relatedTable; ForeignKey = $foreignKey } }
    [void]BelongsTo([string]$relatedTable, [string]$foreignKey) { $this.Associations["belongs_to_$relatedTable"] = @{ Type = "belongs_to"; Table = $relatedTable; ForeignKey = $foreignKey } }

    [void]SetAttribute([string]$key, [object]$value) { $this.Attributes[$key] = $value }
    [object]GetAttribute([string]$key) { return $this.Attributes[$key] }

    [void]On([string]$Event, [scriptblock]$Action) {
        if ($Event -notin @('BeforeSave', 'AfterSave', 'BeforeDelete', 'AfterDelete')) { throw "Invalid event '$Event'." }
        $this.Callbacks[$Event] = $Action
    }

    [void]AddValidator([string]$Column, [string]$Type, [object]$Arg) {
        if ($Type -notin @('Required', 'MaxLength', 'Regex', 'Custom')) { throw "Invalid validator type '$Type'." }
        if (-not $this.Validators.ContainsKey($Column)) { $this.Validators[$Column] = @() }
        $this.Validators[$Column] += @{ Type = $Type; Arg = $Arg }
    }

    [string[]]Validate() {
        $errors = @()
        foreach ($col in $this.Validators.Keys) {
            $val = $this.Attributes[$col]
            foreach ($rule in $this.Validators[$col]) {
                try {
                    switch ($rule.Type) {
                        'Required' { if ($null -eq $val -or ($val -is [string] -and [string]::IsNullOrWhiteSpace($val))) { $errors += '${col} is required'.Replace('${col}', $col) } }
                        'MaxLength' { if ($val -is [string] -and $val.Length -gt [int]$rule.Arg) { $errors += "$col exceeds max length $($rule.Arg)" } }
                        'Regex' { if ($val -is [string] -and ($val -notmatch $rule.Arg)) { $errors += "$col does not match pattern" } }
                        'Custom' { if (-not (& $rule.Arg $val)) { $errors += "$col failed custom validation" } }
                    }
                }
                catch { Write-DbLog ERROR "Validator for column '$col' threw." $_.Exception; $errors += "$col validation error" }
            }
        }
        return $errors
    }

    hidden [void]InvokeCallback([string]$Name) {
    $cb = $this.Callbacks[$Name]; if ($cb) { try { & $cb $this } catch { Write-DbLog ERROR "Callback '$Name' threw." $_.Exception } }
    }

    [void]Save() {
        $errs = $this.Validate(); if ($errs.Count -gt 0) { throw "Validation failed: $($errs -join '; ')" }
        $this.InvokeCallback('BeforeSave')
        try {
            if ($this.Id -eq 0) {
                $keys = $this.Attributes.Keys
                if (-not $keys -or $keys.Count -eq 0) { throw "No attributes set for insert into $($this.TableName)." }
            $this.columns = (($keys | ForEach-Object { ConvertTo-Ident $_ })) -join ", "
                $placeholders = (($keys | ForEach-Object { "@$_" })) -join ", "
            $query = "INSERT INTO $(ConvertTo-Ident $($this.TableName)) (" + $this.columns + ") VALUES ($placeholders); SELECT last_insert_rowid() AS id;"
                $params = @{}; foreach ($k in $keys) { $params[$k] = $this.Attributes[$k] }
                $res = Invoke-DbQuery -Database $this.Database -Query $query -SqlParameters $params
                if ($res -and $res[0] -and $res[0].id) { $this.Id = [int]$res[0].id }
            }
            else {
                if (-not $this.Attributes.Keys -or $this.Attributes.Keys.Count -eq 0) { return }
            $setClause = (($this.Attributes.Keys | ForEach-Object { "$(ConvertTo-Ident $_) = @$_" })) -join ", "
            $query = "UPDATE $(ConvertTo-Ident $($this.TableName)) SET $setClause WHERE id = @id"
                $params = @{ id = $this.Id }; foreach ($k in $this.Attributes.Keys) { $params[$k] = $this.Attributes[$k] }
                [void](Invoke-DbQuery -Database $this.Database -Query $query -SqlParameters $params -NonQuery)
            }
        }
        catch { Write-DbLog ERROR "Error saving record" $_.Exception; throw }
        finally { $this.InvokeCallback('AfterSave') }
    }

    [void]Delete() {
        $this.InvokeCallback('BeforeDelete')
        try {
            if ($this.Id -ne 0) {
            $query = "DELETE FROM $(ConvertTo-Ident $($this.TableName)) WHERE id = @id"
                [void](Invoke-DbQuery -Database $this.Database -Query $query -SqlParameters @{id = $this.Id } -NonQuery)
                $this.Id = 0
            }
        }
        catch { Write-DbLog ERROR "Error deleting record" $_.Exception; throw }
        finally { $this.InvokeCallback('AfterDelete') }
    }

    [object[]]Where([string]$WhereClause, [hashtable]$Params) {
    $sql = "SELECT * FROM $(ConvertTo-Ident $($this.TableName))"
        if ($WhereClause -and $WhereClause.Trim().Length -gt 0) { $sql += " WHERE $WhereClause" }
        $results = Invoke-DbQuery -Database $this.Database -Query $sql -SqlParameters $Params
        $type = $this.GetType()
        $ctorInfo = $type.GetConstructor([type[]]@([string]))
        $records = @()
        foreach ($row in $results) {
            $rec = $ctorInfo.Invoke(@($this.Database))
            if ($row.PSObject.Properties.Name -contains 'id') { $rec.Id = [int]$row.id }
            foreach ($p in $row.PSObject.Properties) { 
                if ($p.Name -ne 'id' -and $p.Name -notin $this.ExcludedProperties) { 
                    $rec.SetAttribute($p.Name, $p.Value) 
                } 
            }            $records += $rec
        }
        return $records
    }

    [psobject]FindById([int]$Id) {
    $sql = "SELECT * FROM $(ConvertTo-Ident $($this.TableName)) WHERE id = @id"
        $res = Invoke-DbQuery -Database $this.Database -Query $sql -SqlParameters @{id = $Id }
        if (-not $res -or $res.Count -eq 0) { return $null }
        $type = $this.GetType()
        $ctorInfo = $type.GetConstructor([type[]]@([string]))
        $rec = $ctorInfo.Invoke(@($this.Database))
        $row = $res[0]
        $rec.Id = [int]$row.id
        foreach ($p in $row.PSObject.Properties) { 
            if ($p.Name -ne 'id' -and $p.Name -notin $this.ExcludedProperties) { 
                $rec.SetAttribute($p.Name, $p.Value) 
            } 
        }
        return $rec
    }

    [object[]] All() {
    $query = "SELECT * FROM $(ConvertTo-Ident $($this.TableName))"
        $results = Invoke-DbQuery -Database $this.Database -Query $query
    
        $objects = @()
        foreach ($row in $results) {
            $obj = [PSCustomObject]@{}
            foreach ($property in $row.PSObject.Properties) {
                $obj | Add-Member -MemberType NoteProperty -Name $property.Name -Value $property.Value
            }
            $objects += $obj
        }
        return $objects
    }

    [psobject]First([string]$OrderBy = 'id ASC') {
    $sql = "SELECT * FROM $(ConvertTo-Ident $($this.TableName)) ORDER BY $OrderBy LIMIT 1"
        $res = Invoke-DbQuery -Database $this.Database -Query $sql
        if (-not $res -or $res.Count -eq 0) { return $null }
        $type = $this.GetType()
        $ctorInfo = $type.GetConstructor([type[]]@([string]))
        $rec = $ctorInfo.Invoke(@($this.Database))
        $row = $res[0]
        $rec.Id = [int]$row.id
        foreach ($p in $row.PSObject.Properties) { 
            if ($p.Name -ne 'id' -and $p.Name -notin $this.ExcludedProperties) { 
                $rec.SetAttribute($p.Name, $p.Value) 
            } 
        }
        return $rec
    }

    [void]InsertMany([System.Collections.IEnumerable]$Rows) {
        $tx = Start-DbTransaction -Database $this.Database
        try {
            foreach ($row in $Rows) {
            $keys = $row.Keys; $this.columns = (($keys | ForEach-Object { ConvertTo-Ident $_ })) -join ', '
                $placeholders = (($keys | ForEach-Object { "@$_" })) -join ', '
            $sql = "INSERT INTO $(ConvertTo-Ident $($this.TableName)) (" + $($this.columns) + ") VALUES ($placeholders)"
                [void](Invoke-DbQuery -Database $this.Database -Query $sql -SqlParameters $row -NonQuery -Transaction $tx)
            }
            Commit-DbTransaction -Database $this.Database -Transaction $tx
        }
        catch { Undo-DbTransaction -Database $this.Database -Transaction $tx; Write-DbLog ERROR "Bulk insert failed" $_.Exception; throw }
    }

    [void]InsertOnConflict([hashtable]$Row, [string[]]$KeyColumns, [hashtable]$UpdateSet) {
    Enable-UniqueIndex -Database $this.Database -Table $this.TableName -Columns $KeyColumns | Out-Null
        # version check
    Enable-UpsertSupported -Database $this.Database
        $cols = $Row.Keys
    $this.columns = (($cols | ForEach-Object { ConvertTo-Ident $_ })) -join ', '
        $placeholders = (($cols | ForEach-Object { "@$_" })) -join ', '
    $onKeys = (($KeyColumns | ForEach-Object { ConvertTo-Ident $_ })) -join ', '
        if (-not $UpdateSet) { $UpdateSet = @{}; foreach ($c in $cols) { if ($KeyColumns -notcontains $c) { $UpdateSet[$c] = "@$c" } } }
    $updateClause = (($UpdateSet.Keys | ForEach-Object { "$(ConvertTo-Ident $_) = $($UpdateSet[$_])" })) -join ', '
    $sql = "INSERT INTO $(ConvertTo-Ident $($this.TableName)) (" + $($this.columns) + ") VALUES ($placeholders) ON CONFLICT($onKeys) DO UPDATE SET $updateClause"
        [void](Invoke-DbQuery -Database $this.Database -Query $sql -SqlParameters $Row -NonQuery)
    }

    [void]BulkUpsert([System.Collections.IEnumerable]$Rows, [string[]]$KeyColumns) {
    Enable-UpsertSupported -Database $this.Database
        $tx = Start-DbTransaction -Database $this.Database
        try {
            foreach ($row in $Rows) { $this.InsertOnConflict($row, $KeyColumns, $null) }
            Commit-DbTransaction -Database $this.Database -Transaction $tx
        }
        catch { Rollback-DbTransaction -Database $this.Database -Transaction $tx; throw }
    }

    [object]Raw([string]$Sql, [hashtable]$Params) { return Invoke-DbQuery -Database $this.Database -Query $Sql -SqlParameters $Params }

    [object[]]GetHasMany([string]$relatedTable) {
        $assoc = $this.Associations["has_many_$relatedTable"]; if (-not $assoc) { throw "No has_many '$relatedTable' defined" }
    $sql = "SELECT * FROM $(ConvertTo-Ident $($assoc.Table)) WHERE $(ConvertTo-Ident $($assoc.ForeignKey)) = @id"
        $results = Invoke-DbQuery -Database $this.Database -Query $sql -SqlParameters @{id = $this.Id }
        $relatedTypeObj = $script:ModelTypeObjects[$assoc.Table]
        $cols = Get-TableColumns -Database $this.Database -TableName $assoc.Table
        $records = @()
        foreach ($row in $results) {
            if ($relatedTypeObj) {
                $ctorInfo = $relatedTypeObj.GetConstructor([type[]]@([string]))
                $rec = $ctorInfo.Invoke(@($this.Database))
            }
            else {
                $rec = [DynamicActiveRecord]::new($assoc.Table, $this.Database, $cols)
            }
            if ($row.PSObject.Properties.Name -contains 'id') { $rec.Id = [int]$row.id }
            foreach ($p in $row.PSObject.Properties) { 
                if ($p.Name -ne 'id' -and $p.Name -notin $this.ExcludedProperties) { 
                    $rec.SetAttribute($p.Name, $p.Value) 
                } 
            }
            $records += $rec
        }
        return $records
    }

    [DynamicActiveRecord]GetBelongsTo([string]$relatedTable) {
        $assoc = $this.Associations["belongs_to_$relatedTable"]; if (-not $assoc) { throw "No belongs_to '$relatedTable' defined" }
        $fkId = $this.Attributes[$assoc.ForeignKey]; if ($null -eq $fkId) { return $null }
    $sql = "SELECT * FROM $(ConvertTo-Ident $($assoc.Table)) WHERE id = @id"
        $res = Invoke-DbQuery -Database $this.Database -Query $sql -SqlParameters @{id = $fkId }
        if (-not $res -or $res.Count -eq 0) { return $null }
        $relatedTypeObj = $script:ModelTypeObjects[$assoc.Table]
        $cols = Get-TableColumns -Database $this.Database -TableName $assoc.Table
        $row = $res[0]
        if ($relatedTypeObj) {
            $ctorInfo = $relatedTypeObj.GetConstructor([type[]]@([string]))
            $rec = $ctorInfo.Invoke(@($this.Database))
        }
        else {
            $rec = [DynamicActiveRecord]::new($assoc.Table, $this.Database, $cols)
        }
        $rec.Id = [int]$row.id
        foreach ($p in $row.PSObject.Properties) { 
            if ($p.Name -ne 'id' -and $p.Name -notin $this.ExcludedProperties) { 
                $rec.SetAttribute($p.Name, $p.Value) 
            } 
        }        return $rec
    }
}
#EndRegion '.\Classes\DynamicActiveRecord.ps1' 255
#Region '.\Public\Add-DbMigration.ps1' -1

function Add-DbMigration {
    param([Parameter(Mandatory)][string]$Database, [Parameter(Mandatory)][string]$Version, [Parameter(Mandatory)][scriptblock]$Up, [scriptblock]$Down)
    Initialize-Db -Database $Database
    $applied = Get-AppliedMigrations -Database $Database
    if ($applied -contains $Version) { Write-DbLog INFO "Migration $Version already applied."; return }
    $tx = Start-DbTransaction -Database $Database
    try {
        & $Up $Database
        Invoke-DbQuery -Database $Database -Query "INSERT INTO schema_migrations(version, applied_at) VALUES(@v, @t)" -SqlParameters @{ v = $Version; t = (Get-Date).ToString('s') } -NonQuery | Out-Null
        Commit-DbTransaction -Database $Database -Transaction $tx; Write-DbLog INFO "Applied migration $Version"
    }
    catch { Undo-DbTransaction -Database $Database -Transaction $tx; Write-DbLog ERROR "Migration $Version failed" $_.Exception; throw }
}
#EndRegion '.\Public\Add-DbMigration.ps1' 14
#Region '.\Public\Close-DbConnections.ps1' -1

function Close-DbConnections {
    foreach ($kvp in $script:DbPool.GetEnumerator()) {
        if ($kvp.Value -and $kvp.Value.State -eq 'Open') { $kvp.Value.Close(); $kvp.Value.Dispose() }
    }
    $script:DbPool.Clear()
}
#EndRegion '.\Public\Close-DbConnections.ps1' 7
#Region '.\Public\Commit-DbTransaction.ps1' -1

function Commit-DbTransaction {
    param([Parameter(Mandatory)][string]$Database, [System.Data.SQLite.SQLiteTransaction]$Transaction)
    if ($Transaction) { $Transaction.Commit(); $Transaction.Dispose(); return }
    # Fallback path without transaction object: no-op
}
#EndRegion '.\Public\Commit-DbTransaction.ps1' 6
#Region '.\Public\Confirm-DbForeignKey.ps1' -1

function Confirm-DbForeignKey {
    param(
        [Parameter(Mandatory)][string]$Database,
        [Parameter(Mandatory)][string]$From,      # table with FK column
        [Parameter(Mandatory)][string]$Column,    # fk column in From
        [Parameter(Mandatory)][string]$To,        # referenced table
        [string]$RefColumn = 'id',
        [ValidateSet('NO ACTION', 'RESTRICT', 'CASCADE', 'SET NULL')][string]$OnDelete = 'NO ACTION'
    )
    Initialize-Db -Database $Database

    # SQLite can't add FKs easily post-creation; use triggers for enforcement & optional cascade.
    $checkTrig = "trg_fk_${From}_${Column}_check"
    $delTrig = "trg_fk_${From}_${Column}_ondelete"

    $quotedFrom = ConvertTo-Ident $From; $quotedCol = ConvertTo-Ident $Column; $quotedTo = ConvertTo-Ident $To; $quotedRef = ConvertTo-Ident $RefColumn

    $checkSql = @"
CREATE TRIGGER IF NOT EXISTS $(ConvertTo-Ident $checkTrig)
BEFORE INSERT ON $quotedFrom
FOR EACH ROW BEGIN
    SELECT RAISE(ABORT, 'FK violation: $From.$Column → $To.$RefColumn')
    WHERE NEW.$quotedCol IS NOT NULL AND NOT EXISTS (SELECT 1 FROM $quotedTo WHERE $quotedTo.$quotedRef = NEW.$quotedCol);
END;
"@
    Invoke-DbQuery -Database $Database -Query $checkSql -NonQuery | Out-Null

    $updSql = @"
CREATE TRIGGER IF NOT EXISTS $(ConvertTo-Ident ($checkTrig + '_upd'))
BEFORE UPDATE OF $quotedCol ON $quotedFrom
FOR EACH ROW BEGIN
    SELECT RAISE(ABORT, 'FK violation: $From.$Column → $To.$RefColumn')
    WHERE NEW.$quotedCol IS NOT NULL AND NOT EXISTS (SELECT 1 FROM $quotedTo WHERE $quotedTo.$quotedRef = NEW.$quotedCol);
END;
"@
    Invoke-DbQuery -Database $Database -Query $updSql -NonQuery | Out-Null

    if ($OnDelete -eq 'CASCADE') {
        $cascadeSql = @"
CREATE TRIGGER IF NOT EXISTS $(ConvertTo-Ident $delTrig)
AFTER DELETE ON $quotedTo
FOR EACH ROW BEGIN
    DELETE FROM $quotedFrom WHERE $quotedFrom.$quotedCol = OLD.$quotedRef;
END;
"@
        Invoke-DbQuery -Database $Database -Query $cascadeSql -NonQuery | Out-Null
    }

    # Record as confirmed
    Invoke-DbQuery -Database $Database -Query @"
INSERT INTO __fks__(table_name,column_name,ref_table,ref_column,confidence,status,on_delete)
VALUES(@t,@c,@rt,@rc,1.0,'confirmed',@od)
ON CONFLICT(table_name,column_name) DO UPDATE SET ref_table=excluded.ref_table, ref_column=excluded.ref_column, status='confirmed', on_delete=@od
"@ -SqlParameters @{ t = $From; c = $Column; rt = $To; rc = $RefColumn; od = $OnDelete } -NonQuery | Out-Null
}
#EndRegion '.\Public\Confirm-DbForeignKey.ps1' 56
#Region '.\Public\ConvertTo-Ident.ps1' -1

function ConvertTo-Ident { param([string]$Name) return '"' + ($Name -replace '"', '""') + '"' }

#EndRegion '.\Public\ConvertTo-Ident.ps1' 3
#Region '.\Public\Enable-ForeignKeysPragma.ps1' -1

function Enable-ForeignKeysPragma {
    param([Parameter(Mandatory)][string]$Database)
    if ($script:PragmaSet[$Database]) { return }
    try {
        Invoke-SqliteQuery -DataSource $Database -Query 'PRAGMA foreign_keys = ON;'
        $script:PragmaSet[$Database] = $true
        Write-DbLog DEBUG "PRAGMA foreign_keys = ON (fallback)"
    }
    catch { Write-DbLog WARN "Unable to set PRAGMA foreign_keys in fallback" $_.Exception }
}

#EndRegion '.\Public\Enable-ForeignKeysPragma.ps1' 12
#Region '.\Public\Enable-UniqueIndex.ps1' -1

function Enable-UniqueIndex {
    param([Parameter(Mandatory)][string]$Database, [Parameter(Mandatory)][string]$Table, [Parameter(Mandatory)][string[]]$Columns)
    $idxName = "ux_${Table}_" + (($Columns -join "_") -replace '[^A-Za-z0-9_]', '_')
    $exists = Invoke-DbQuery -Database $Database -Query "SELECT name FROM sqlite_master WHERE type='index' AND name=@n" -SqlParameters @{ n = $idxName }
    if (-not $exists -or $exists.Count -eq 0) {
        $cols = (($Columns | ForEach-Object { ConvertTo-Ident $_ })) -join ', '
        Invoke-DbQuery -Database $Database -Query "CREATE UNIQUE INDEX IF NOT EXISTS $(ConvertTo-Ident $idxName) ON $(ConvertTo-Ident $Table) ($cols)" -NonQuery | Out-Null
    }
    return $idxName
}

#EndRegion '.\Public\Enable-UniqueIndex.ps1' 12
#Region '.\Public\Enable-UpsertSupported.ps1' -1

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

#EndRegion '.\Public\Enable-UpsertSupported.ps1' 13
#Region '.\Public\Export-DynamicModelsFromCatalog.ps1' -1

function Export-DynamicModelsFromCatalog {
    param([Parameter(Mandatory)][string]$Database)

    Initialize-Db -Database $Database
    Update-DbCatalog -Database $Database

    $tables = Invoke-DbQuery -Database $Database -Query "SELECT table_name FROM __tables__"
    foreach ($t in $tables) {
        $tn = $t.table_name
        if ($tn -like 'sqlite_%' -or $tn -in @('__tables__', '__columns__', '__fks__', 'schema_migrations')) { continue }

        $cols = Invoke-DbQuery -Database $Database -Query "PRAGMA table_info($(ConvertTo-Ident $tn))" | Sort-Object -Property cid
        $colNames = $cols | ForEach-Object { $_.name }
        if (-not $colNames -or $colNames.Count -eq 0) { continue }

        $hasMany = @{}; $belongsTo = @{}
        $fksFrom = Invoke-DbQuery -Database $Database -Query "SELECT column_name, ref_table FROM __fks__ WHERE table_name=@t AND status='confirmed'" -SqlParameters @{ t = $tn }
        foreach ($fk in $fksFrom) { $belongsTo[$fk.ref_table] = $fk.column_name }
        $fksTo = Invoke-DbQuery -Database $Database -Query "SELECT table_name, column_name FROM __fks__ WHERE ref_table=@t AND status='confirmed'" -SqlParameters @{ t = $tn }
        foreach ($fk in $fksTo) { $hasMany[$fk.table_name] = $fk.column_name }

        $typeName = "Dynamic" + ($tn -replace '[^a-zA-Z0-9]', '' -replace '^.', { $_.Value.ToUpper() })
        if (-not ([System.Management.Automation.PSTypeName]$typeName).Type) {
            $typeName = New-DynamicModel -TableName $tn -Database $Database -Columns $colNames -HasMany $hasMany -BelongsTo $belongsTo
        }
        $script:ModelTypes[$tn] = $typeName
        $script:ModelTypeObjects[$tn] = ([System.Management.Automation.PSTypeName]$typeName).Type
    }

    return $script:ModelTypes
}

#EndRegion '.\Public\Export-DynamicModelsFromCatalog.ps1' 33
#Region '.\Public\Find-DbRelationships.ps1' -1

function Find-DbRelationships {
    param([Parameter(Mandatory)][string]$Database)

    function Get-RefColumn {
        param(
            [string]$Base,      # e.g., "user" from user_id
            [string]$RefTable,  # candidate ref table name: "user" or "users"
            [string[]]$RefCols  # column names in ref table
        )

        $norm = {
            param($s) ($s -replace '_', '').ToLower()
        }

        $baseN = & $norm $Base
        $refN = & $norm $RefTable

        $best = @{ name = $null; score = 0.0 }

        foreach ($col in $RefCols) {
            $c = $col
            $cN = & $norm $c

            $score =
            if ($cN -eq 'id') { 1.00 }
            elseif ($cN -eq ($refN + 'id') -or $cN -eq ($baseN + 'id')) { 0.95 }
            elseif ($c -match '_id$') { 0.85 }
            elseif ($cN -like ($baseN + '*') -or $cN -like ($refN + '*')) { 0.75 }
            elseif ($cN -like '*id*') { 0.60 }
            else { 0.0 }

            if ($score -gt $best.score) {
                $best.name = $c
                $best.score = $score
            }
        }

        if (-not $best.name) {
            # absolute fallback
            $best = @{ name = 'id'; score = 0.50 }
        }

        return $best
    }

    Initialize-Db -Database $Database

    $suggestions = New-Object System.Collections.ArrayList

    $tables = Invoke-DbQuery -Database $Database -Query "SELECT table_name FROM __tables__"
    $tableNames = $tables | ForEach-Object { $_.table_name }

    foreach ($tn in $tableNames) {
        $cols = Invoke-DbQuery -Database $Database -Query "SELECT column_name FROM __columns__ WHERE table_name=@t" -SqlParameters @{ t = $tn }
        foreach ($col in $cols) {
            $c = $col.column_name
            if ($c -match '^(.*)_id$') {
                $base = $Matches[1]
                $candidates = $tableNames | Where-Object { $_ -eq $base -or $_ -eq ($base + 's') }

                foreach ($ref in $candidates) {
                    $refCols = (Invoke-DbQuery -Database $Database -Query "SELECT column_name FROM __columns__ WHERE table_name=@rt" -SqlParameters @{ rt = $ref } | ForEach-Object { $_.column_name })
                    $pick = Get-RefColumn -Base $base -RefTable $ref -RefCols $refCols

                    Invoke-DbQuery -Database $Database -Query @"
INSERT INTO __fks__(table_name,column_name,ref_table,ref_column,confidence,status)
VALUES(@t,@c,@rt,@rc,@conf,'suggested')
ON CONFLICT(table_name,column_name)
DO UPDATE SET
  ref_table=excluded.ref_table,
  ref_column=excluded.ref_column,
  confidence=excluded.confidence,
  status=COALESCE(__fks__.status,'suggested')
"@ -SqlParameters @{ t = $tn; c = $c; rt = $ref; rc = $pick.name; conf = [math]::Round($pick.score, 2) } -NonQuery | Out-Null

                    [void]$suggestions.Add([pscustomobject]@{
                        table_name  = $tn
                        column_name = $c
                        ref_table   = $ref
                        ref_column  = $pick.name
                        confidence  = [math]::Round($pick.score, 2)
                        status      = 'suggested'
                    })
                }
            }
        }
    }
    return $suggestions
}

#EndRegion '.\Public\Find-DbRelationships.ps1' 91
#Region '.\Public\Get-AppliedMigrations.ps1' -1

function Get-AppliedMigrations {
    param([Parameter(Mandatory)][string]$Database)
    Initialize-Db -Database $Database
    $rows = Invoke-DbQuery -Database $Database -Query "SELECT version FROM schema_migrations ORDER BY id"
    return $rows | ForEach-Object { $_.version }
}
#EndRegion '.\Public\Get-AppliedMigrations.ps1' 7
#Region '.\Public\Get-DbConnection.ps1' -1

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
#EndRegion '.\Public\Get-DbConnection.ps1' 12
#Region '.\Public\Get-TableColumns.ps1' -1

function Get-TableColumns {
    param([Parameter(Mandatory)][string]$Database, [Parameter(Mandatory)][string]$TableName)
    $cols = Invoke-DbQuery -Database $Database -Query "PRAGMA table_info($(ConvertTo-Ident $TableName))" | Sort-Object -Property cid
    return ($cols | ForEach-Object { $_.name })
}

#EndRegion '.\Public\Get-TableColumns.ps1' 7
#Region '.\Public\Import-CsvToSqlite.ps1' -1

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

    $columnTypes = Test-ColumnTypes -Csv $csv -Headers $headers
    foreach ($h in $headers) { if (-not $columnTypes[$h]) { $columnTypes[$h] = 'TEXT' } }

    $quotedCols = ($headers | ForEach-Object { "$(ConvertTo-Ident $_) $($columnTypes[$_])" }) -join ", "
    # Handle schema creation based on SchemaMode
    if ($SchemaMode -ne 'AppendOnly') {
        if (-not [string]::IsNullOrWhiteSpace($quotedCols)) {
            $createQuery = "CREATE TABLE IF NOT EXISTS $(ConvertTo-Ident $TableName) ($quotedCols)"
            Invoke-DbQuery -Database $Database -Query $createQuery -NonQuery | Out-Null
        }
    } else {
        # AppendOnly: ensure table exists; do not create
        $exists = Invoke-DbQuery -Database $Database -Query "SELECT name FROM sqlite_master WHERE type='table' AND name=@t" -SqlParameters @{ t = $TableName }
        if (-not $exists -or $exists.Count -eq 0) { throw "AppendOnly mode: table '$TableName' does not exist." }
    }

    # Evolve schema
    $existing = Invoke-DbQuery -Database $Database -Query "PRAGMA table_info($(ConvertTo-Ident $TableName))"
    $existingNames = $existing | ForEach-Object { $_.name }
    if ($SchemaMode -in @('Relaxed')) {
        foreach ($h in $headers) {
            if ($existingNames -notcontains $h) {
                $sql = "ALTER TABLE $(ConvertTo-Ident $TableName) ADD COLUMN $(ConvertTo-Ident $h) $($columnTypes[$h])"
                Invoke-DbQuery -Database $Database -Query $sql -NonQuery | Out-Null
            }
        }
    }
    elseif ($SchemaMode -eq 'Strict') {
        foreach ($h in $headers) { if ($existingNames -notcontains $h) { throw "Strict mode: missing column $h in $TableName" } }
    }
    elseif ($SchemaMode -eq 'AppendOnly') {
        # No schema changes allowed
    }

    # Insert data
    $tx = Start-DbTransaction -Database $Database
    try {
        $count = 0
        foreach ($row in $csv) {
            $keys = $row.PSObject.Properties.Name
            $columns = (($keys | ForEach-Object { ConvertTo-Ident $_ })) -join ", "
            $placeholders = (($keys | ForEach-Object { "@$_" })) -join ", "
            $query = "INSERT INTO $(ConvertTo-Ident $TableName) ($columns) VALUES ($placeholders)"
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
    catch { Undo-DbTransaction -Database $Database -Transaction $tx; throw }

    Update-DbCatalog -Database $Database -SourceCsvPath $CsvPath -Table $TableName
    return $headers
}
#EndRegion '.\Public\Import-CsvToSqlite.ps1' 90
#Region '.\Public\Initialize-Db.ps1' -1

function Initialize-Db {
    param([Parameter(Mandatory)][string]$Database)
    $sql = @"
CREATE TABLE IF NOT EXISTS schema_migrations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    version TEXT NOT NULL UNIQUE,
    applied_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS __tables__ (
    table_name TEXT PRIMARY KEY,
    source TEXT,
    created_at TEXT,
    csv_hash TEXT,
    rowcount INTEGER,
    sample_json TEXT
);
CREATE TABLE IF NOT EXISTS __columns__ (
    table_name TEXT,
    column_name TEXT,
    data_type TEXT,
    nullable INTEGER,
    pk INTEGER,
    example_values_json TEXT,
    PRIMARY KEY (table_name, column_name)
);
CREATE TABLE IF NOT EXISTS __fks__ (
    table_name TEXT,
    column_name TEXT,
    ref_table TEXT,
    ref_column TEXT,
    confidence REAL,
    status TEXT,
    on_delete TEXT,
    on_update TEXT,
    PRIMARY KEY (table_name, column_name)
);
"@
    # Execute full statements, splitting by semicolon terminators
    $stmts = $sql -split ";\s*`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($stmt in $stmts) { Invoke-DbQuery -Database $Database -Query $stmt -NonQuery | Out-Null }
}
#EndRegion '.\Public\Initialize-Db.ps1' 42
#Region '.\Public\Initialize-ORMVars.ps1' -1

Function Initialize-ORMVars {
    <#
    .SYNOPSIS
    Initializes internal ORM state and (optionally) applies configuration.

    .DESCRIPTION
    Sets up module-wide state such as connection pools and logging defaults.
    You may configure values directly via parameters or by providing a settings
    script that returns a hashtable with keys: DbPath, LogPath, LogLevel.

    .PARAMETER DbPath
    Optional default database path to store in module state.

    .PARAMETER LogPath
    Path to the log file. If omitted, logs are written via Write-Verbose.

    .PARAMETER LogLevel
    Logging threshold. One of: DEBUG, INFO, WARN, ERROR.

    .PARAMETER SettingsPath
    Path to a PowerShell script that returns a hashtable of settings.
    Example:
        @{ DbPath = 'C:\data\app.db'; LogPath = 'C:\logs\db.log'; LogLevel = 'DEBUG' }
    #>
    param (
        [string]$DbPath,
        [string]$LogPath,
        [ValidateSet('DEBUG','INFO','WARN','ERROR')][string]$LogLevel,
        [string]$SettingsPath
    )

    # Initialize base state
    $script:DbPool = @{}
    $script:DbLogPath = $null
    $script:DbLogLevel = 'INFO'
    $script:PragmaSet = @{}
    $script:ModelTypes = @{}
    $script:ModelTypeObjects = @{}
    $global:DynamicClassScripts = [System.Collections.ArrayList]::new()

    # Optionally load settings from a script returning a hashtable
    $cfg = $null
    if ($SettingsPath) {
        if (-not (Test-Path -LiteralPath $SettingsPath)) { throw "SettingsPath not found: $SettingsPath" }
        try { $cfg = . $SettingsPath } catch { throw "Failed to load settings from '$SettingsPath': $($_.Exception.Message)" }
        if ($cfg -and $cfg -is [hashtable]) {
            if ($cfg.ContainsKey('DbPath')) { $DbPath = $cfg['DbPath'] }
            if ($cfg.ContainsKey('LogPath')) { $LogPath = $cfg['LogPath'] }
            if ($cfg.ContainsKey('LogLevel')) { $LogLevel = $cfg['LogLevel'] }
        }
    }

    # Apply settings (settings file and/or explicit parameters). Explicit parameters override, but both paths end here.
    if ($LogPath) { $script:DbLogPath = $LogPath }
    if ($LogLevel) { $script:DbLogLevel = $LogLevel }
    if ($DbPath) { $script:DbDefaultPath = $DbPath }

    # Summarize configuration for users at INFO level
    try { Write-DbLog INFO ("ORM initialized. Level={0}, LogPath={1}, DefaultDb={2}" -f $script:DbLogLevel, ($script:DbLogPath ?? '(none)'), ($script:DbDefaultPath ?? '(none)')) } catch { }
}

# Initialize defaults automatically on module import (no settings file here)
Initialize-ORMVars | Out-Null
#EndRegion '.\Public\Initialize-ORMVars.ps1' 64
#Region '.\Public\Invoke-DbQuery.ps1' -1

function Invoke-DbQuery {
    param(
        [Parameter(Mandatory)][string]$Database,
        [Parameter(Mandatory)][string]$Query,
        [hashtable]$SqlParameters,
        [switch]$Scalar,
        [switch]$NonQuery,
        [switch]$AsDataTable,
        [System.Data.SQLite.SQLiteTransaction]$Transaction
    )

    $paramPairs = ''
    if ($SqlParameters) { $paramPairs = (($SqlParameters.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ') }
    Write-DbLog DEBUG "SQL: $Query | Params: $paramPairs"

    $conn = Get-DbConnection -Database $Database
    if ($conn -and $conn.State -eq 'Open') {
        $cmd = $conn.CreateCommand(); $cmd.CommandText = $Query
        if ($Transaction) { $cmd.Transaction = $Transaction }
        if ($SqlParameters) {
            foreach ($k in $SqlParameters.Keys) {
                $p = $cmd.CreateParameter(); $p.ParameterName = "@$k"; $p.Value = $SqlParameters[$k]; [void]$cmd.Parameters.Add($p)
            }
        }
        try {
            if ($Scalar) { return $cmd.ExecuteScalar() }
            elseif ($NonQuery) { return $cmd.ExecuteNonQuery() }
            else {
                $dt = New-Object System.Data.DataTable
                $da = New-Object System.Data.SQLite.SQLiteDataAdapter($cmd); [void]$da.Fill($dt)
                if ($AsDataTable) { return $dt } else { return $dt | Select-Object * }
            }
        }
    catch { Write-DbLog ERROR "Invoke-DbQuery error" $_.Exception; throw }
        finally { $cmd.Dispose() }
    }
    else {
        # Fallback path via PSSQLite
        Enable-ForeignKeysPragma -Database $Database
        try {
            if ($Scalar) {
                $q = Invoke-SqliteQuery -DataSource $Database -Query $Query -SqlParameters $SqlParameters
                if ($q -and $q.Count -gt 0) {
                    $first = $q | Select-Object -First 1
                    $firstProp = $first.PSObject.Properties | Select-Object -First 1
                    if ($firstProp) { return $firstProp.Value } else { return $null }
                }
                else { return $null }
            }
            elseif ($NonQuery) {
                [void](Invoke-SqliteQuery -DataSource $Database -Query $Query -SqlParameters $SqlParameters)
            }
            else {
                return Invoke-SqliteQuery -DataSource $Database -Query $Query -SqlParameters $SqlParameters
            }
        }
        catch { Write-DbLog ERROR "Invoke-DbQuery (PSSQLite) error" $_.Exception; throw }
    }
}
#EndRegion '.\Public\Invoke-DbQuery.ps1' 60
#Region '.\Public\New-DbQuery.ps1' -1

function New-DbQuery { param([Parameter(Mandatory)][string]$Database, [Parameter(Mandatory)][string]$From) return [DbQuery]::new($Database, $From) }
#EndRegion '.\Public\New-DbQuery.ps1' 2
#Region '.\Public\New-DynamicModel.ps1' -1

function New-DynamicModel {
    param (
        [Parameter(Mandatory)][string]$TableName,
        [Parameter(Mandatory)][string]$Database,
        [Parameter(Mandatory)][string[]]$Columns,
        [hashtable]$HasMany = @{},
        [hashtable]$BelongsTo = @{}
    )

    if (-not $global:DynamicClassScripts) {
        $global:DynamicClassScripts = [System.Collections.ArrayList]::new()
    } elseif ($global:DynamicClassScripts -isnot [System.Collections.ArrayList]) {
        # Safety: Wrap non-ArrayList (e.g., single PSCustomObject or other) into a new ArrayList
        $newList = [System.Collections.ArrayList]::new()
        if ($global:DynamicClassScripts) {
            [void]$newList.Add($global:DynamicClassScripts)
        }
        $global:DynamicClassScripts = $newList
    }

    # Ensure base class exists first
    if (-not ([System.Management.Automation.PSTypeName]'DynamicActiveRecord').Type) {
        throw "DynamicActiveRecord must be loaded before emitting '$TableName'."
    }

    # ---- Build safe PascalCase name and prefix with 'Dynamic'
    # e.g. "assets", "user_assets", "user-assets" => "Assets", "UserAssets"
    $words = ($TableName -replace '[^A-Za-z0-9]+', ' ') -split '\s+' | Where-Object { $_ }
    $pascal = if ($words) { ($words | ForEach-Object { $_.Substring(0, 1).ToUpper() + $_.Substring(1) }) -join '' } else { 'Model' }
    if ($pascal -match '^[0-9]') { $pascal = '_' + $pascal }
    $typeName = 'Dynamic' + $pascal

    # Already present? Just return the name
    if (([System.Management.Automation.PSTypeName]$typeName).Type) { return $typeName }

    # ---- Hidden backing fields template
    $backingFieldTemplate = @'
    hidden [object] $_{0}
'@

    # ---- Property-like method template (overloaded methods)
    $propTemplate = @'
    # Property-like methods for {1}
    [object] {0}() {{
        return $this.GetAttribute('{1}')
    }}
    
    [void] {0}([object] $value) {{
        $this.SetAttribute('{1}', $value)
    }}
'@

    # Generate backing fields and property methods (skip 'id' if it's special)
    $backingFields = ($Columns |
        Where-Object { $_ -ne 'id' } |
        ForEach-Object {
            # Sanitize the class property identifier
            $propName = ($_ -replace '[^A-Za-z0-9_]', '_')
            if ($propName -match '^[0-9]') { $propName = '_' + $propName }
            $backingFieldTemplate -f $propName
        }
    ) -join "`n"

    $propDefs = ($Columns |
        Where-Object { $_ -ne 'id' } |
        ForEach-Object {
            # Sanitize the class property identifier but keep the original column key for Get/SetAttribute
            $propName = ($_ -replace '[^A-Za-z0-9_]', '_')
            if ($propName -match '^[0-9]') { $propName = '_' + $propName }
            $propTemplate -f $propName, $_
        }
    ) -join "`n"

    # ---- Constructor column list for base(...)
    $ctorCols = ($Columns | ForEach-Object { "'$_'" }) -join ', '

    # ---- Associations (emit literal $this.* without string expansion)
    $hmLines = ($HasMany.GetEnumerator() | ForEach-Object {
            '        $this.HasMany(''{0}'',''{1}'');' -f $_.Key, $_.Value
        }) -join "`n"

    $btLines = ($BelongsTo.GetEnumerator() | ForEach-Object {
            '        $this.BelongsTo(''{0}'',''{1}'');' -f $_.Key, $_.Value
        }) -join "`n"

    # ---- Class template with property-like methods
    $classTemplate = @'
class {0} : DynamicActiveRecord {{
    
{6}
    
    {0}([string]$database) : base('{1}', $database, @({2})) {{
{3}
{4}
    }}

{5}
}}
'@

    $classDefinition = $classTemplate -f $typeName, $TableName, $ctorCols, $hmLines, $btLines, $propDefs, $backingFields

    # ---- Emit and load in caller's scope
    $temp = Join-Path $env:TEMP ("dyn_{0}.ps1" -f $TableName)
    if (Test-Path -LiteralPath $temp) {
        Remove-Item -LiteralPath $temp -ErrorAction SilentlyContinue
    }
    Set-Content -LiteralPath $temp -Value $classDefinition -Encoding UTF8

[void]$global:DynamicClassScripts.Add([pscustomobject]@{
        Table     = $TableName
        ModelPath = $temp
    })

    return $typeName
}
#EndRegion '.\Public\New-DynamicModel.ps1' 117
#Region '.\Public\Set-DbLogging.ps1' -1

function Set-DbLogging {
    param(
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR')] [string]$Level = 'INFO',
        [string]$Path
    )
    $script:DbLogLevel = $Level
    if ($PSBoundParameters.ContainsKey('Path')) { $script:DbLogPath = $Path }
}
#EndRegion '.\Public\Set-DbLogging.ps1' 9
#Region '.\Public\Set-DynamicORMClass.ps1' -1

Function Set-DynamicORMClass {
    foreach ($script in $Global:DynamicClassScripts) {
        $classDefinition = Get-Content $script.ModelPath -Raw
        Invoke-Expression $classDefinition
    }
}
#EndRegion '.\Public\Set-DynamicORMClass.ps1' 7
#Region '.\Public\Start-DbTransaction.ps1' -1

function Start-DbTransaction {
    param([Parameter(Mandatory)][string]$Database)
    $conn = Get-DbConnection -Database $Database
    if ($conn -and $conn.State -eq 'Open') { return $conn.BeginTransaction() }
    # Fallback path (PSSQLite): no persistent transaction support is guaranteed
    Enable-ForeignKeysPragma -Database $Database
    return $null
}
#EndRegion '.\Public\Start-DbTransaction.ps1' 9
#Region '.\Public\Test-ColumnTypes.ps1' -1

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

#EndRegion '.\Public\Test-ColumnTypes.ps1' 20
#Region '.\Public\Undo-DbTransaction.ps1' -1

function Undo-DbTransaction {
    param([Parameter(Mandatory)][string]$Database, [System.Data.SQLite.SQLiteTransaction]$Transaction)
    if ($Transaction) { $Transaction.Rollback(); $Transaction.Dispose(); return }
    # Fallback path without transaction object: no-op
}

#EndRegion '.\Public\Undo-DbTransaction.ps1' 7
#Region '.\Public\Update-DbCatalog.ps1' -1

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
#EndRegion '.\Public\Update-DbCatalog.ps1' 44
#Region '.\Public\Write-DbLog.ps1' -1

function Write-DbLog {
    param(
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR')][string]$Level,
        [string]$Message,
        [System.Exception]$Exception
    )
    $levels = @('DEBUG', 'INFO', 'WARN', 'ERROR')
    if ($levels.IndexOf($Level) -lt $levels.IndexOf($script:DbLogLevel)) { return }
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    $line = "[$ts][$Level] $Message"
    if ($Exception) { $line += " :: " + $Exception.Message }
    if ($script:DbLogPath) { Add-Content -Path $script:DbLogPath -Value $line } else { Write-Verbose $line }
}
#EndRegion '.\Public\Write-DbLog.ps1' 14
