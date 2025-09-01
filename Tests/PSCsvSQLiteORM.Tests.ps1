# Pester tests for PSCsvSQLiteORM module
# This file checks that all exported functions exist and can be called


# Import the module from the output directory as PSCsvSQLiteORM
$moduleFolder = 'C:\Users\Jaga\Documents\Scripts\PSCsvSqliteORM\PSCsvSQLiteORM\output\PSCsvSQLiteORM'
Import-Module $moduleFolder -Force

Describe 'PSCsvSQLiteORM Exported Functions' {
    $functions = @(
        'Add-DbMigration',
        'Close-DbConnections',
        'Complete-DbTransaction',
        'Confirm-DbForeignKey',
        'Export-DynamicModelsFromCatalog',
        'Enable-ForeignKeysPragma',
        'Enable-UniqueIndex',
        'Enable-UpsertSupported',
        'Get-AppliedMigrations',
        'Get-DbConnection',
        'Get-TableColumns',
        'Import-CsvToSqlite',
        'Test-ColumnTypes',
        'Initialize-Db',
        'Initialize-ORMVars',
        'Invoke-DbQuery',
        'New-DbQuery',
        'New-DynamicModel',
        'ConvertTo-Ident',
        'Undo-DbTransaction',
        'Set-DbLogging',
        'Set-DynamicORMClass',
        'Start-DbTransaction',
        'Find-DbRelationships',
        'Update-DbCatalog',
        'Write-DbLog'
    )
    foreach ($fn in $functions) {
        It "Function $fn should exist in the module" -TestCases @{ Name = $fn } {
            param($Name)
            (Get-Command $Name -Module PSCsvSQLiteORM) | Should -Not -BeNullOrEmpty
        }
    }
}
