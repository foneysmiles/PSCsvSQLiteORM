function ConvertTo-Ident { param([string]$Name) return '"' + ($Name -replace '"', '""') + '"' }

