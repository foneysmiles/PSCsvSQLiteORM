function Set-DbLogging {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Low')]
    param(
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR')] [string]$Level = 'INFO',
        [string]$Path
    )
    $proceed = $true
    if ($PSCmdlet) { $proceed = $PSCmdlet.ShouldProcess('ModuleState', "Set logging to $Level") }
    if ($proceed) {
        $script:DbLogLevel = $Level
        if ($PSBoundParameters.ContainsKey('Path')) { $script:DbLogPath = $Path }
    }
}
