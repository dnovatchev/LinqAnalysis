<#
.SYNOPSIS
    Populates dbo.CorpusMeasurement from CorpusMeasurement.csv.

.DESCRIPTION
    This procedure reads a CorpusMeasurement.csv produced by the
    LINQ corpus measurement workflow and inserts its measurement
    into dbo.CorpusMeasurement.

    dbo.CorpusMeasurement contains exactly one row per Repository.

    The procedure therefore enforces the following behavior:

      * Repository does not exist:
            insert the measurement.

      * Repository exists with the same CommitHash:
            treat the measurement as already populated, and exit
            without making any changes.

      * Repository exists with a different CommitHash:
            fail without changing the database.

    CorpusMeasurement.csv is the only CSV input required.

.PARAMETER CorpusMeasurementCsvPath
    Complete path to CorpusMeasurement.csv.

.PARAMETER ServerInstance
    SQL Server instance. Defaults to the local default instance.

.PARAMETER Database
    SQL Server database. Defaults to LinqCorpus.

.EXAMPLE
    .\PopulateSQLCorpusMeasurementFromCorpus.ps1 `
        C:\LinqCorpus\Analyzer\Results\dotnet-runtime\CorpusMeasurement.csv

.EXAMPLE
    .\PopulateSQLCorpusMeasurementFromCorpus.ps1 `
        C:\LinqCorpus\Analyzer\Results\dotnet-runtime\CorpusMeasurement.csv `
        -ServerInstance ".\SQLEXPRESS" `
        -Database "LinqCorpus"
#>

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string] $CorpusMeasurementCsvPath,

    [Parameter(Mandatory = $false)]
    [string] $ServerInstance = ".",

    [Parameter(Mandatory = $false)]
    [string] $Database = "LinqCorpus"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------------------
# Validate input file.
# ----------------------------------------------------------------------

if (-not (Test-Path -LiteralPath $CorpusMeasurementCsvPath -PathType Leaf)) {
    throw "CorpusMeasurement.csv not found: $CorpusMeasurementCsvPath"
}

$CorpusMeasurementCsvPath =
    (Resolve-Path -LiteralPath $CorpusMeasurementCsvPath).Path

Write-Host "Input:    $CorpusMeasurementCsvPath"
Write-Host "Server:   $ServerInstance"
Write-Host "Database: $Database"

# ----------------------------------------------------------------------
# Read CSV.
# ----------------------------------------------------------------------

$rows = @(Import-Csv -LiteralPath $CorpusMeasurementCsvPath)

if ($rows.Count -eq 0) {
    throw "CorpusMeasurement.csv contains no data rows."
}

if ($rows.Count -ne 1) {
    throw "Expected exactly one row in CorpusMeasurement.csv; found $($rows.Count)."
}

$row = $rows[0]

# ----------------------------------------------------------------------
# Validate required columns.
# ----------------------------------------------------------------------

$requiredColumns = @(
    'Repository',
    'CommitHash',
    'AnalyzerSDK',
    'TotalFiles',
    'CsprojFiles',
    'CSharpFiles',
    'CSharpBytes',
    'CSharpMB',
    'CSharpLines'
)

$actualColumns = @(
    $row.PSObject.Properties.Name
)

foreach ($column in $requiredColumns) {
    if ($column -notin $actualColumns) {
        throw "CorpusMeasurement.csv is missing required column '$column'."
    }
}

# ----------------------------------------------------------------------
# Validate textual values.
# ----------------------------------------------------------------------

$repository = ([string]$row.Repository).Trim()
$commitHash = ([string]$row.CommitHash).Trim()
$analyzerSDK = ([string]$row.AnalyzerSDK).Trim()

if ([string]::IsNullOrWhiteSpace($repository)) {
    throw "Repository is empty."
}

if ($repository.Length -gt 40) {
    throw "Repository exceeds the database limit of 40 characters: '$repository'"
}

if ([string]::IsNullOrWhiteSpace($commitHash)) {
    throw "CommitHash is empty."
}

if ($commitHash -notmatch '^[0-9a-fA-F]{40}$') {
    throw "CommitHash is not a valid 40-character hexadecimal Git hash: '$commitHash'"
}

if ([string]::IsNullOrWhiteSpace($analyzerSDK)) {
    throw "AnalyzerSDK is empty."
}

# ----------------------------------------------------------------------
# Parse numeric values.
# ----------------------------------------------------------------------

[int]$totalFiles = 0
[int]$csprojFiles = 0
[int]$cSharpFiles = 0
[long]$cSharpBytes = 0
[decimal]$cSharpMB = 0
[long]$cSharpLines = 0

if (-not [int]::TryParse(
        [string]$row.TotalFiles,
        [ref]$totalFiles)) {
    throw "Invalid TotalFiles value: '$($row.TotalFiles)'"
}

if (-not [int]::TryParse(
        [string]$row.CsprojFiles,
        [ref]$csprojFiles)) {
    throw "Invalid CsprojFiles value: '$($row.CsprojFiles)'"
}

if (-not [int]::TryParse(
        [string]$row.CSharpFiles,
        [ref]$cSharpFiles)) {
    throw "Invalid CSharpFiles value: '$($row.CSharpFiles)'"
}

if (-not [long]::TryParse(
        [string]$row.CSharpBytes,
        [ref]$cSharpBytes)) {
    throw "Invalid CSharpBytes value: '$($row.CSharpBytes)'"
}

if (-not [decimal]::TryParse(
        [string]$row.CSharpMB,
        [System.Globalization.NumberStyles]::Number,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [ref]$cSharpMB)) {
    throw "Invalid CSharpMB value: '$($row.CSharpMB)'"
}

if (-not [long]::TryParse(
        [string]$row.CSharpLines,
        [ref]$cSharpLines)) {
    throw "Invalid CSharpLines value: '$($row.CSharpLines)'"
}

# ----------------------------------------------------------------------
# Validate non-negative measurements and basic relationships.
# ----------------------------------------------------------------------

if ($totalFiles -lt 0) {
    throw "TotalFiles cannot be negative."
}

if ($csprojFiles -lt 0) {
    throw "CsprojFiles cannot be negative."
}

if ($cSharpFiles -lt 0) {
    throw "CSharpFiles cannot be negative."
}

if ($cSharpFiles -gt $totalFiles) {
    throw "CSharpFiles ($cSharpFiles) cannot exceed TotalFiles ($totalFiles)."
}

if ($cSharpBytes -lt 0) {
    throw "CSharpBytes cannot be negative."
}

if ($cSharpMB -lt 0) {
    throw "CSharpMB cannot be negative."
}

if ($cSharpLines -lt 0) {
    throw "CSharpLines cannot be negative."
}

# ----------------------------------------------------------------------
# Connect to SQL Server.
# ----------------------------------------------------------------------

$connectionString =
    "Server=$ServerInstance;Database=$Database;Integrated Security=True;TrustServerCertificate=True;"

Add-Type -AssemblyName System.Data

$connection =
    [System.Data.SqlClient.SqlConnection]::new($connectionString)

$connection.Open()

$transaction = $connection.BeginTransaction()

try {

    # ------------------------------------------------------------------
    # Check whether this Repository already exists.
    #
    # Repository is UNIQUE in CorpusMeasurement.
    # ------------------------------------------------------------------

    $cmd = $connection.CreateCommand()
    $cmd.Transaction = $transaction

    $cmd.CommandText = `
        'SELECT CommitHash ' +
        'FROM dbo.CorpusMeasurement ' +
        'WHERE Repository = @Repository;'

    $null = $cmd.Parameters.Add(
        "@Repository",
        [System.Data.SqlDbType]::VarChar,
        40
    )

    $cmd.Parameters["@Repository"].Value = $repository

    $existingCommitHash = $cmd.ExecuteScalar()

    $cmd.Dispose()

    if ($null -ne $existingCommitHash) {

        $existingCommitHash = ([string]$existingCommitHash).Trim()

        if ($existingCommitHash -ieq $commitHash) {

            $transaction.Commit()

            Write-Host ""
            Write-Host "CorpusMeasurement already populated."
            Write-Host "  Repository: $repository"
            Write-Host "  CommitHash: $commitHash"
            Write-Host "  No changes made."

            return
        }

        throw @"
Repository '$repository' already has a CorpusMeasurement row.

Existing CommitHash: $existingCommitHash
CSV CommitHash:      $commitHash

The database permits only one CorpusMeasurement row per Repository.
The existing measurement was NOT modified.
"@
    }

    # ------------------------------------------------------------------
    # Insert the new measurement.
    # ------------------------------------------------------------------

    $cmd = $connection.CreateCommand()
    $cmd.Transaction = $transaction

    $cmd.CommandText = `
        'INSERT INTO dbo.CorpusMeasurement ' +
        '(Repository, CommitHash, AnalyzerSDK, TotalFiles, ' +
        ' CsprojFiles, CSharpFiles, CSharpBytes, CSharpMB, CSharpLines) ' +
        'VALUES ' +
        '(@Repository, @CommitHash, @AnalyzerSDK, @TotalFiles, ' +
        ' @CsprojFiles, @CSharpFiles, @CSharpBytes, @CSharpMB, @CSharpLines);'

    $null = $cmd.Parameters.Add(
        "@Repository",
        [System.Data.SqlDbType]::VarChar,
        40
    )

    $null = $cmd.Parameters.Add(
        "@CommitHash",
        [System.Data.SqlDbType]::Char,
        40
    )

    $null = $cmd.Parameters.Add(
        "@AnalyzerSDK",
        [System.Data.SqlDbType]::VarChar,
        30
    )

    $null = $cmd.Parameters.Add(
        "@TotalFiles",
        [System.Data.SqlDbType]::Int
    )

    $null = $cmd.Parameters.Add(
        "@CsprojFiles",
        [System.Data.SqlDbType]::Int
    )

    $null = $cmd.Parameters.Add(
        "@CSharpFiles",
        [System.Data.SqlDbType]::Int
    )

    $null = $cmd.Parameters.Add(
        "@CSharpBytes",
        [System.Data.SqlDbType]::BigInt
    )

    $null = $cmd.Parameters.Add(
        "@CSharpMB",
        [System.Data.SqlDbType]::Decimal
    )

    $cmd.Parameters["@CSharpMB"].Precision = 12
    $cmd.Parameters["@CSharpMB"].Scale = 2

    $null = $cmd.Parameters.Add(
        "@CSharpLines",
        [System.Data.SqlDbType]::BigInt
    )

    $cmd.Parameters["@Repository"].Value = $repository
    $cmd.Parameters["@CommitHash"].Value = $commitHash
    $cmd.Parameters["@AnalyzerSDK"].Value = $analyzerSDK
    $cmd.Parameters["@TotalFiles"].Value = $totalFiles
    $cmd.Parameters["@CsprojFiles"].Value = $csprojFiles
    $cmd.Parameters["@CSharpFiles"].Value = $cSharpFiles
    $cmd.Parameters["@CSharpBytes"].Value = $cSharpBytes
    $cmd.Parameters["@CSharpMB"].Value = $cSharpMB
    $cmd.Parameters["@CSharpLines"].Value = $cSharpLines

    [void]$cmd.ExecuteNonQuery()

    $cmd.Dispose()

    $transaction.Commit()

    Write-Host ""
    Write-Host "CorpusMeasurement inserted successfully."
    Write-Host "  Repository:  $repository"
    Write-Host "  CommitHash:  $commitHash"
    Write-Host "  AnalyzerSDK: $analyzerSDK"
    Write-Host "  TotalFiles:  $totalFiles"
    Write-Host "  CsprojFiles: $csprojFiles"
    Write-Host "  CSharpFiles: $cSharpFiles"
    Write-Host "  CSharpBytes: $cSharpBytes"
    Write-Host "  CSharpMB:    $cSharpMB"
    Write-Host "  CSharpLines: $cSharpLines"
}
catch {
    try {
        $transaction.Rollback()
    }
    catch {
        Write-Warning "Rollback failed: $($_.Exception.Message)"
    }

    Write-Error "CorpusMeasurement import failed. Transaction rolled back."
    throw
}
finally {
    if ($connection.State -ne [System.Data.ConnectionState]::Closed) {
        $connection.Close()
    }

    $connection.Dispose()
}