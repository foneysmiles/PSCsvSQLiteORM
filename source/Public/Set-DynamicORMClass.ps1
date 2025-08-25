Function Set-DynamicORMClass {
    foreach ($script in $Global:DynamicClassScripts) {
        $classDefinition = Get-Content $script.ModelPath -Raw
        Invoke-Expression $classDefinition
    }
}