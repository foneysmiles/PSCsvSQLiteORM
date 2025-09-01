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
