param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectFilesCsvPath,

    [string]$ServerInstance = ".",

    [string]$Database = "LinqCorpus"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Validate input
# ---------------------------------------------------------------------------

if (-not (Test-Path -LiteralPath $ProjectFilesCsvPath -PathType Leaf)) {
    throw "ProjectFiles CSV file not found: $ProjectFilesCsvPath"
}

Write-Host "Reading: $ProjectFilesCsvPath"

$rows = @(Import-Csv -LiteralPath $ProjectFilesCsvPath)

if ($rows.Count -eq 0) {
    throw "ProjectFiles CSV is empty."
}

# ---------------------------------------------------------------------------
# Validate CSV columns
# ---------------------------------------------------------------------------

$requiredColumns = @(
    "Repository",
    "CommitHash",
    "Project",
    "FilePath"
)

$actualColumns = @($rows[0].PSObject.Properties.Name)

foreach ($column in $requiredColumns) {
    if ($column -notin $actualColumns) {
        throw "Required CSV column '$column' is missing."
    }
}

# ---------------------------------------------------------------------------
# Each ProjectFiles.csv represents one corpus.
# Verify that Repository and CommitHash are consistent throughout the CSV.
# ---------------------------------------------------------------------------

$repositories = @(
    $rows |
        ForEach-Object { $_.Repository } |
        Sort-Object -Unique
)

$commitHashes = @(
    $rows |
        ForEach-Object { $_.CommitHash } |
        Sort-Object -Unique
)

if ($repositories.Count -ne 1) {
    throw "Expected exactly one Repository; found $($repositories.Count)."
}

if ($commitHashes.Count -ne 1) {
    throw "Expected exactly one CommitHash; found $($commitHashes.Count)."
}

$repository = $repositories[0]
$commitHash = $commitHashes[0]

if ([string]::IsNullOrWhiteSpace($repository)) {
    throw "Repository is empty."
}

if ($commitHash.Length -ne 40) {
    throw "CommitHash must contain exactly 40 characters: '$commitHash'"
}

# ---------------------------------------------------------------------------
# Normalize the CSV.
#
# The analyzer may encounter the same Project/FilePath combination more than
# once because of shared projects. ProjectFiles has a primary key on:
#
#   Repository + CommitHash + Project + FilePath
#
# Therefore repeated identical encounters represent one logical row.
# ---------------------------------------------------------------------------

$seen = [System.Collections.Generic.HashSet[string]]::new()

$duplicateRows = 0

$table = New-Object System.Data.DataTable

[void]$table.Columns.Add("Repository", [string])
[void]$table.Columns.Add("CommitHash", [string])
[void]$table.Columns.Add("Project", [string])
[void]$table.Columns.Add("FilePath", [string])

foreach ($row in $rows) {

    if ([string]::IsNullOrWhiteSpace($row.Project)) {
        throw "A ProjectFiles row has an empty Project."
    }

    if ([string]::IsNullOrWhiteSpace($row.FilePath)) {
        throw "A ProjectFiles row has an empty FilePath."
    }

    $key = '{0}|{1}|{2}|{3}' -f `
        $row.Repository,
        $row.CommitHash,
        $row.Project,
        $row.FilePath

    if (-not $seen.Add($key)) {
        $duplicateRows++
        continue
    }

    $dataRow = $table.NewRow()

    $dataRow["Repository"] = $row.Repository
    $dataRow["CommitHash"] = $row.CommitHash
    $dataRow["Project"] = $row.Project
    $dataRow["FilePath"] = $row.FilePath

    [void]$table.Rows.Add($dataRow)
}

$distinctRows = $table.Rows.Count

Write-Host ""
Write-Host "Repository           : $repository"
Write-Host "CommitHash           : $commitHash"
Write-Host "CSV rows             : $($rows.Count)"
Write-Host "Duplicate encounters : $duplicateRows"
Write-Host "Distinct ProjectFiles: $distinctRows"
Write-Host ""

# ---------------------------------------------------------------------------
# SQL connection
# ---------------------------------------------------------------------------

$connectionString =
    "Server=$ServerInstance;" +
    "Database=$Database;" +
    "Integrated Security=True;" +
    "TrustServerCertificate=True;"

$connection = [System.Data.SqlClient.SqlConnection]::new($connectionString)

try {
    $connection.Open()

    # -----------------------------------------------------------------------
    # Verify that the corresponding CorpusMeasurement exists.
    # -----------------------------------------------------------------------

    $command = $connection.CreateCommand()

    $command.CommandText = @"
SELECT COUNT(*)
FROM dbo.CorpusMeasurement
WHERE Repository = @Repository
  AND CommitHash = @CommitHash;
"@

    [void]$command.Parameters.Add(
        [System.Data.SqlClient.SqlParameter]::new(
            "@Repository",
            [System.Data.SqlDbType]::VarChar,
            100
        )
    )

    [void]$command.Parameters.Add(
        [System.Data.SqlClient.SqlParameter]::new(
            "@CommitHash",
            [System.Data.SqlDbType]::Char,
            40
        )
    )

    $command.Parameters["@Repository"].Value = $repository
    $command.Parameters["@CommitHash"].Value = $commitHash

    $measurementCount = [int]$command.ExecuteScalar()

    if ($measurementCount -ne 1) {
        throw @"
Expected exactly one CorpusMeasurement row for:

Repository = $repository
CommitHash = $commitHash

Found: $measurementCount
"@
    }

    # -----------------------------------------------------------------------
    # Make sure this particular corpus/commit has not already been loaded.
    #
    # Other repositories/commits are allowed to be present.
    # -----------------------------------------------------------------------

    $command = $connection.CreateCommand()

    $command.CommandText = @"
SELECT COUNT(*)
FROM dbo.ProjectFiles
WHERE Repository = @Repository
  AND CommitHash = @CommitHash;
"@

    [void]$command.Parameters.Add(
        [System.Data.SqlClient.SqlParameter]::new(
            "@Repository",
            [System.Data.SqlDbType]::VarChar,
            100
        )
    )

    [void]$command.Parameters.Add(
        [System.Data.SqlClient.SqlParameter]::new(
            "@CommitHash",
            [System.Data.SqlDbType]::Char,
            40
        )
    )

    $command.Parameters["@Repository"].Value = $repository
    $command.Parameters["@CommitHash"].Value = $commitHash

    $existingCorpusRows = [int]$command.ExecuteScalar()

    if ($existingCorpusRows -ne 0) {
        throw @"
ProjectFiles already contains $existingCorpusRows rows for:

Repository = $repository
CommitHash = $commitHash

No rows were inserted.
"@
    }

    # -----------------------------------------------------------------------
    # Bulk load the normalized rows directly into dbo.ProjectFiles.
    # -----------------------------------------------------------------------

    $bulkCopy = [System.Data.SqlClient.SqlBulkCopy]::new($connection)

    try {
        $bulkCopy.DestinationTableName = "dbo.ProjectFiles"
        $bulkCopy.BatchSize = 5000
        $bulkCopy.BulkCopyTimeout = 0

        [void]$bulkCopy.ColumnMappings.Add("Repository", "Repository")
        [void]$bulkCopy.ColumnMappings.Add("CommitHash", "CommitHash")
        [void]$bulkCopy.ColumnMappings.Add("Project", "Project")
        [void]$bulkCopy.ColumnMappings.Add("FilePath", "FilePath")

        Write-Host "Loading $distinctRows distinct rows into dbo.ProjectFiles..."

        $bulkCopy.WriteToServer($table)
    }
    finally {
        $bulkCopy.Dispose()
    }

    # -----------------------------------------------------------------------
    # Verify the number of rows loaded for this corpus.
    # -----------------------------------------------------------------------

    $command = $connection.CreateCommand()

    $command.CommandText = @"
SELECT COUNT(*)
FROM dbo.ProjectFiles
WHERE Repository = @Repository
  AND CommitHash = @CommitHash;
"@

    [void]$command.Parameters.Add(
        [System.Data.SqlClient.SqlParameter]::new(
            "@Repository",
            [System.Data.SqlDbType]::VarChar,
            100
        )
    )

    [void]$command.Parameters.Add(
        [System.Data.SqlClient.SqlParameter]::new(
            "@CommitHash",
            [System.Data.SqlDbType]::Char,
            40
        )
    )

    $command.Parameters["@Repository"].Value = $repository
    $command.Parameters["@CommitHash"].Value = $commitHash

    $sqlCount = [int]$command.ExecuteScalar()

    if ($sqlCount -ne $distinctRows) {
        throw @"
ProjectFiles row-count verification failed.

Distinct CSV rows : $distinctRows
SQL rows           : $sqlCount
"@
    }

    # -----------------------------------------------------------------------
    # Calculate the number of genuinely shared files for this corpus.
    #
    # A file is shared when it belongs to more than one distinct Project.
    # Exact duplicate Project/FilePath encounters have already been removed.
    # -----------------------------------------------------------------------

    $command = $connection.CreateCommand()

    $command.CommandText = @"
SELECT COUNT(*)
FROM
(
    SELECT FilePath
    FROM dbo.ProjectFiles
    WHERE Repository = @Repository
      AND CommitHash = @CommitHash
    GROUP BY FilePath
    HAVING COUNT(*) > 1
) AS SharedFiles;
"@

    [void]$command.Parameters.Add(
        [System.Data.SqlClient.SqlParameter]::new(
            "@Repository",
            [System.Data.SqlDbType]::VarChar,
            100
        )
    )

    [void]$command.Parameters.Add(
        [System.Data.SqlClient.SqlParameter]::new(
            "@CommitHash",
            [System.Data.SqlDbType]::Char,
            40
        )
    )

    $command.Parameters["@Repository"].Value = $repository
    $command.Parameters["@CommitHash"].Value = $commitHash

    $sharedFileCount = [int]$command.ExecuteScalar()

    Write-Host ""
    Write-Host "========== SUMMARY =========="
    Write-Host "Repository            : $repository"
    Write-Host "CommitHash            : $commitHash"
    Write-Host "CSV rows              : $($rows.Count)"
    Write-Host "Duplicate encounters  : $duplicateRows"
    Write-Host "Distinct ProjectFiles : $distinctRows"
    Write-Host "SQL rows              : $sqlCount"
    Write-Host "Shared files          : $sharedFileCount"
    Write-Host "Status                : SUCCESS"
}
finally {
    if ($connection.State -ne [System.Data.ConnectionState]::Closed) {
        $connection.Close()
    }

    $connection.Dispose()
}