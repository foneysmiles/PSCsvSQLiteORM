function New-DbQuery {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory)][string]$Database,
        [Parameter(Mandatory)][string]$From
    )
    if ($PSCmdlet) { $null = $PSCmdlet.ShouldProcess("DbQuery from '$From'", 'Create object') }
    return [DbQuery]::new($Database, $From)
}
