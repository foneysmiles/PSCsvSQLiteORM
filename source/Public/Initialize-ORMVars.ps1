Function Initialize-ORMVars {
    param (
        [string]$DbPath,
        [string]$LogPath,
        [string]$LogLevel
    )
    $script:DbPool = @{}     # optional shared connections
    $script:DbLogPath = $null
    $script:DbLogLevel = 'INFO'  # DEBUG|INFO|WARN|ERROR
    $script:PragmaSet = @{}  # track PRAGMA foreign_keys for fallback
    $script:ModelTypes = @{} # table_name -> type name
    $script:ModelTypeObjects = @{} # table_name -> [type]
    $global:DynamicClassScripts = [System.Collections.ArrayList]::new() # track dynamically generated classes
}