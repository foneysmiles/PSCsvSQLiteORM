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
