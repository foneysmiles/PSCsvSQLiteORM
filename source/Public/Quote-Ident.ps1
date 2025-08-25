function Quote-Ident { param([string]$Name) return '"' + ($Name -replace '"', '""') + '"' }
