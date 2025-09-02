function New-DynamicModel {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param (
        [Parameter(Mandatory)][string]$TableName,
        [Parameter(Mandatory)][string]$Database,
        [Parameter(Mandatory)][string[]]$Columns,
        [hashtable]$HasMany = @{},
        [hashtable]$BelongsTo = @{}
    )

    if (-not $script:DynamicClassScripts) {
        $script:DynamicClassScripts = [System.Collections.ArrayList]::new()
    } elseif ($script:DynamicClassScripts -isnot [System.Collections.ArrayList]) {
        # Safety: Wrap non-ArrayList (e.g., single PSCustomObject or other) into a new ArrayList
        $newList = [System.Collections.ArrayList]::new()
        if ($script:DynamicClassScripts) {
            [void]$newList.Add($script:DynamicClassScripts)
        }
        $script:DynamicClassScripts = $newList
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
    $proceed = $true; if ($PSCmdlet) { $proceed = $PSCmdlet.ShouldProcess($temp, 'Write dynamic class file') }
    if ($proceed) {
        Set-Content -LiteralPath $temp -Value $classDefinition -Encoding UTF8
    }

    $proceed = $true; if ($PSCmdlet) { $proceed = $PSCmdlet.ShouldProcess('DynamicClassScripts', "Register $typeName") }
    if ($proceed) {
        [void]$script:DynamicClassScripts.Add([pscustomobject]@{
        Table     = $TableName
        ModelPath = $temp
        })
    }

    return $typeName
}
