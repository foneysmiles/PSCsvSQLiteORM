function Set-DbLogging {
    param(
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR')] [string]$Level = 'INFO',
        [string]$Path
    )
    $script:DbLogLevel = $Level
    if ($PSBoundParameters.ContainsKey('Path')) { $script:DbLogPath = $Path }
}
