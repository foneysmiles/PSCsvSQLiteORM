function Close-DbConnections {
    foreach ($kvp in $script:DbPool.GetEnumerator()) {
        if ($kvp.Value -and $kvp.Value.State -eq 'Open') { $kvp.Value.Close(); $kvp.Value.Dispose() }
    }
    $script:DbPool.Clear()
}