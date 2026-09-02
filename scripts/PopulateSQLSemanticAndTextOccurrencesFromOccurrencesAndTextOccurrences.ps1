$server = "localhost"
$database = "LinqCorpus"

$conn = New-Object System.Data.SqlClient.SqlConnection
$conn.ConnectionString =
    "Server=$server;Database=$database;Integrated Security=True;TrustServerCertificate=True"

$conn.Open()

try {
    foreach ($repo in 'serilog','dotnet-efcore','dotnet-runtime') {

        Write-Host "`n=== $repo ===" -ForegroundColor Cyan

        # ------------------------------------------------------------
        # Get the commit hash recorded for this repository.
        # ------------------------------------------------------------

        $cmd = $conn.CreateCommand()
        $cmd.CommandText = @"
SELECT CommitHash
FROM dbo.CorpusMeasurement
WHERE Repository = @Repository;
"@

        [void]$cmd.Parameters.Add("@Repository",
            [System.Data.SqlDbType]::VarChar, 100)
        $cmd.Parameters["@Repository"].Value = $repo

        $commitHash = $cmd.ExecuteScalar()

        if ($null -eq $commitHash) {
            throw "No CorpusMeasurement row found for '$repo'."
        }

        Write-Host "CommitHash: $commitHash"

        # ============================================================
        # OCCURRENCES
        # ============================================================

        $csvPath = ".\Results\$repo\occurrences.csv"
        $rows = @(Import-Csv $csvPath)

        Write-Host "Occurrences CSV rows: $($rows.Count)"

        $table = New-Object System.Data.DataTable

        [void]$table.Columns.Add("Repository", [string])
        [void]$table.Columns.Add("CommitHash", [string])
        [void]$table.Columns.Add("Project", [string])
        [void]$table.Columns.Add("Operator", [string])
        [void]$table.Columns.Add("Api", [string])
        [void]$table.Columns.Add("Kind", [string])
        [void]$table.Columns.Add("FilePath", [string])
        [void]$table.Columns.Add("Line", [int])

        foreach ($row in $rows) {
            $newRow = $table.NewRow()

            $newRow["Repository"] = $row.Repository
            $newRow["CommitHash"] = $commitHash
            $newRow["Project"] = $row.Project
            $newRow["Operator"] = $row.Operator
            $newRow["Api"] = $row.API
            $newRow["Kind"] = $row.Kind
            $newRow["FilePath"] = $row.File
            $newRow["Line"] = [int]$row.Line

            [void]$table.Rows.Add($newRow)
        }

        $bulk = New-Object System.Data.SqlClient.SqlBulkCopy($conn)
        $bulk.DestinationTableName = "dbo.Occurrences"
        $bulk.BatchSize = 5000

        foreach ($column in $table.Columns) {
            [void]$bulk.ColumnMappings.Add(
                $column.ColumnName,
                $column.ColumnName)
        }

        $bulk.WriteToServer($table)
        $bulk.Close()

        Write-Host "Inserted $($rows.Count) Occurrences rows." -ForegroundColor Green

        # ============================================================
        # TEXT OCCURRENCES
        # ============================================================

        $csvPath = ".\Results\$repo\text-occurrences.csv"
        $rows = @(Import-Csv $csvPath)

        Write-Host "TextOccurrences CSV rows: $($rows.Count)"

        $table = New-Object System.Data.DataTable

        [void]$table.Columns.Add("Repository", [string])
        [void]$table.Columns.Add("CommitHash", [string])
        [void]$table.Columns.Add("FilePath", [string])
        [void]$table.Columns.Add("Line", [int])
        [void]$table.Columns.Add("Operator", [string])

        foreach ($row in $rows) {
            $newRow = $table.NewRow()

            $newRow["Repository"] = $row.Repository
            $newRow["CommitHash"] = $commitHash
            $newRow["FilePath"] = $row.File
            $newRow["Line"] = [int]$row.Line
            $newRow["Operator"] = $row.Operator

            [void]$table.Rows.Add($newRow)
        }

        $bulk = New-Object System.Data.SqlClient.SqlBulkCopy($conn)
        $bulk.DestinationTableName = "dbo.TextOccurrences"
        $bulk.BatchSize = 5000

        foreach ($column in $table.Columns) {
            [void]$bulk.ColumnMappings.Add(
                $column.ColumnName,
                $column.ColumnName)
        }

        $bulk.WriteToServer($table)
        $bulk.Close()

        Write-Host "Inserted $($rows.Count) TextOccurrences rows." -ForegroundColor Green
    }
}
finally {
    $conn.Close()
    $conn.Dispose()
}