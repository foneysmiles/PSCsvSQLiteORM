function New-DbQuery { param([Parameter(Mandatory)][string]$Database, [Parameter(Mandatory)][string]$From) return [DbQuery]::new($Database, $From) }
