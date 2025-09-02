Function Set-DynamicORMClass {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param()
    foreach ($script in $script:DynamicClassScripts) {
        if (-not $script -or -not $script.ModelPath) { continue }
        $path = $script.ModelPath
        if (-not (Test-Path -LiteralPath $path)) { Write-DbLog -Level WARN -Message "Dynamic model path not found: $path"; continue }
        $target = "class from $path"
        $proceed = $true; if ($PSCmdlet) { $proceed = $PSCmdlet.ShouldProcess($target, 'Load') }
        if ($proceed) {
            . $path
        }
    }
}
