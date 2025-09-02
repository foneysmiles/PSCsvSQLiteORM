function ConvertTo-Ident {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { throw "Invalid identifier: value is null or empty" }
    # Allow word chars, space, dash, underscore, and dot. Reject everything else to block SQL injection via identifiers.
    if ($Name -match '[^\w\s\-_.]') {
        throw "Invalid identifier: '$Name' contains illegal characters"
    }
    return '"' + ($Name -replace '"', '""') + '"'
}
