<#
.SYNOPSIS
    Populates dbo.Chains and dbo.ChainMethods from chains.csv.

.DESCRIPTION
    This procedure reads a chains.csv produced by the LINQ corpus
    analysis workflow and populates two SQL tables:

        dbo.Chains
        dbo.ChainMethods

    chains.csv is the only CSV input required.

    Repository, Project, ChainId, source positions, and the textual
    Methods chain come from chains.csv.

    The authoritative CommitHash is obtained from dbo.CorpusMeasurement
    using Repository. CorpusMeasurement must already contain exactly
    one row for the repository.

    Each method name in the Methods field is resolved against dbo.Methods
    using its (Api, Operator) pair. The resulting dbo.Methods.Id is stored
    in dbo.ChainMethods.MethodId.

    The entire operation is performed in one SQL transaction. Therefore,
    either both tables are populated successfully or neither table is
    changed.

.PARAMETER ChainsCsvPath
    Complete path to chains.csv.

.PARAMETER ServerInstance
    SQL Server instance. Defaults to the local default instance.

.PARAMETER Database
    SQL Server database. Defaults to LinqCorpus.

.EXAMPLE
    .\PopulateSQLChainsFromCorpus.ps1 `
        .\Results\dotnet-runtime\chains.csv

.EXAMPLE
    .\PopulateSQLChainsFromCorpus.ps1 `
        .\Results\dotnet-runtime\chains.csv `
        -ServerInstance "." `
        -Database "LinqCorpus"
#>

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string] $ChainsCsvPath,

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

if (-not (Test-Path -LiteralPath $ChainsCsvPath -PathType Leaf)) {
    throw "chains.csv not found: $ChainsCsvPath"
}

$ChainsCsvPath =
    (Resolve-Path -LiteralPath $ChainsCsvPath).Path

Write-Host "Input:    $ChainsCsvPath"
Write-Host "Server:   $ServerInstance"
Write-Host "Database: $Database"

# ----------------------------------------------------------------------
# Read CSV.
# ----------------------------------------------------------------------

$chains = @(Import-Csv -LiteralPath $ChainsCsvPath)

if ($chains.Count -eq 0) {
    throw "chains.csv contains no data rows."
}

Write-Host "Chains:   $($chains.Count)"

# ----------------------------------------------------------------------
# Validate required columns.
# ----------------------------------------------------------------------

$requiredColumns = @(
    'ChainId',
    'Repository',
    'Project',
    'LeftmostPosition',
    'RightmostPosition',
    'Methods'
)

$actualColumns = @(
    $chains[0].PSObject.Properties.Name
)

foreach ($column in $requiredColumns) {
    if ($column -notin $actualColumns) {
        throw "chains.csv is missing required column '$column'."
    }
}

# ----------------------------------------------------------------------
# All rows in a chains.csv are expected to belong to one repository.
# ----------------------------------------------------------------------

$repositories = @(
    $chains |
        ForEach-Object { ([string]$_.Repository).Trim() } |
        Sort-Object -Unique
)

if ($repositories.Count -ne 1) {
    throw "chains.csv must contain exactly one Repository; found $($repositories.Count)."
}

$repository = $repositories[0]

if ([string]::IsNullOrWhiteSpace($repository)) {
    throw "Repository is empty."
}

if ($repository.Length -gt 100) {
    throw "Repository exceeds the database limit of 100 characters: '$repository'"
}

# ----------------------------------------------------------------------
# SQL Server connection.
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
    # Obtain authoritative CommitHash from dbo.CorpusMeasurement.
    # ------------------------------------------------------------------

    $cmd = $connection.CreateCommand()
    $cmd.Transaction = $transaction

    $cmd.CommandText =
        'SELECT CommitHash ' +
        'FROM dbo.CorpusMeasurement ' +
        'WHERE Repository = @Repository;'

    $null = $cmd.Parameters.Add(
        "@Repository",
        [System.Data.SqlDbType]::VarChar,
        100
    )

    $cmd.Parameters["@Repository"].Value = $repository

    $commitHashObject = $cmd.ExecuteScalar()

    $cmd.Dispose()

    if ($null -eq $commitHashObject) {
        throw @"
Repository '$repository' does not exist in dbo.CorpusMeasurement.

Populate dbo.CorpusMeasurement first by running
PopulateSQLCorpusMeasurementFromCorpus.ps1.
"@
    }

    $commitHash = ([string]$commitHashObject).Trim()

    if ($commitHash -notmatch '^[0-9a-fA-F]{40}$') {
        throw "Invalid CommitHash in dbo.CorpusMeasurement: '$commitHash'"
    }

    Write-Host "Repository: $repository"
    Write-Host "CommitHash: $commitHash"

    # ------------------------------------------------------------------
    # Prepare reusable Commands.
    # ------------------------------------------------------------------

    $methodCommand = $connection.CreateCommand()
    $methodCommand.Transaction = $transaction

    $methodCommand.CommandText =
        'SELECT Id ' +
        'FROM dbo.Methods ' +
        'WHERE Api = @Api ' +
        '  AND Operator = @Operator;'

    $null = $methodCommand.Parameters.Add(
        "@Api",
        [System.Data.SqlDbType]::VarChar,
        20
    )

    $null = $methodCommand.Parameters.Add(
        "@Operator",
        [System.Data.SqlDbType]::VarChar,
        100
    )

    # ------------------------------------------------------------------
    # Insert Chains.
    #
    # We use parameterized commands and obtain the MethodIds while
    # processing the same CSV row.
    # ------------------------------------------------------------------

    $chainCommand = $connection.CreateCommand()
    $chainCommand.Transaction = $transaction

    $chainCommand.CommandText = @'
INSERT INTO dbo.Chains
(
    Repository,
    CommitHash,
    ChainId,
    Project,
    LeftmostLine,
    LeftmostColumn,
    RightmostLine,
    RightmostColumn,
    ChainLength
)
VALUES
(
    @Repository,
    @CommitHash,
    @ChainId,
    @Project,
    @LeftmostLine,
    @LeftmostColumn,
    @RightmostLine,
    @RightmostColumn,
    @ChainLength
);
'@

    $null = $chainCommand.Parameters.Add(
        "@Repository",
        [System.Data.SqlDbType]::VarChar,
        100
    )

    $null = $chainCommand.Parameters.Add(
        "@CommitHash",
        [System.Data.SqlDbType]::Char,
        40
    )

    $null = $chainCommand.Parameters.Add(
        "@ChainId",
        [System.Data.SqlDbType]::VarChar,
        300
    )

    $null = $chainCommand.Parameters.Add(
        "@Project",
        [System.Data.SqlDbType]::VarChar,
        100
    )

    $null = $chainCommand.Parameters.Add(
        "@LeftmostLine",
        [System.Data.SqlDbType]::Int
    )

    $null = $chainCommand.Parameters.Add(
        "@LeftmostColumn",
        [System.Data.SqlDbType]::Int
    )

    $null = $chainCommand.Parameters.Add(
        "@RightmostLine",
        [System.Data.SqlDbType]::Int
    )

    $null = $chainCommand.Parameters.Add(
        "@RightmostColumn",
        [System.Data.SqlDbType]::Int
    )

    $null = $chainCommand.Parameters.Add(
        "@ChainLength",
        [System.Data.SqlDbType]::TinyInt
    )

    # ------------------------------------------------------------------
    # Insert ChainMethods.
    # ------------------------------------------------------------------

    $chainMethodCommand = $connection.CreateCommand()
    $chainMethodCommand.Transaction = $transaction

    $chainMethodCommand.CommandText = @'
INSERT INTO dbo.ChainMethods
(
    Repository,
    CommitHash,
    ChainId,
    PositionInChain,
    MethodId
)
VALUES
(
    @Repository,
    @CommitHash,
    @ChainId,
    @PositionInChain,
    @MethodId
);
'@

    $null = $chainMethodCommand.Parameters.Add(
        "@Repository",
        [System.Data.SqlDbType]::VarChar,
        100
    )

    $null = $chainMethodCommand.Parameters.Add(
        "@CommitHash",
        [System.Data.SqlDbType]::Char,
        40
    )

    $null = $chainMethodCommand.Parameters.Add(
        "@ChainId",
        [System.Data.SqlDbType]::VarChar,
        300
    )

    $null = $chainMethodCommand.Parameters.Add(
        "@PositionInChain",
        [System.Data.SqlDbType]::TinyInt
    )

    $null = $chainMethodCommand.Parameters.Add(
        "@MethodId",
        [System.Data.SqlDbType]::Int
    )

    # ------------------------------------------------------------------
    # Process chains.
    # ------------------------------------------------------------------

    $chainNumber = 0

    foreach ($row in $chains) {

        $chainNumber++

        $chainId = ([string]$row.ChainId).Trim()
        $project = ([string]$row.Project).Trim()
        $leftmostPosition = ([string]$row.LeftmostPosition).Trim()
        $rightmostPosition = ([string]$row.RightmostPosition).Trim()
        $methodsText = ([string]$row.Methods).Trim()

        if ([string]::IsNullOrWhiteSpace($chainId)) {
            throw "Row $chainNumber has an empty ChainId."
        }

        if ($chainId.Length -gt 300) {
            throw "Row $chainNumber ChainId exceeds 300 characters."
        }

        if ([string]::IsNullOrWhiteSpace($project)) {
            throw "Row $chainNumber has an empty Project."
        }

        if ($project.Length -gt 100) {
            throw "Row $chainNumber Project exceeds 100 characters."
        }

        if ([string]::IsNullOrWhiteSpace($methodsText)) {
            throw "Row $chainNumber has an empty Methods field."
        }

        # --------------------------------------------------------------
        # Parse positions.
        #
        # Expected form:
        #
        #     138,19
        #     139,121
        # --------------------------------------------------------------

        $leftParts = $leftmostPosition -split ','
        $rightParts = $rightmostPosition -split ','

        if ($leftParts.Count -ne 2) {
            throw "Row $chainNumber has invalid LeftmostPosition '$leftmostPosition'."
        }

        if ($rightParts.Count -ne 2) {
            throw "Row $chainNumber has invalid RightmostPosition '$rightmostPosition'."
        }

        [int]$leftmostLine = 0
        [int]$leftmostColumn = 0
        [int]$rightmostLine = 0
        [int]$rightmostColumn = 0

        if (-not [int]::TryParse($leftParts[0], [ref]$leftmostLine)) {
            throw "Row $chainNumber has invalid LeftmostLine '$($leftParts[0])'."
        }

        if (-not [int]::TryParse($leftParts[1], [ref]$leftmostColumn)) {
            throw "Row $chainNumber has invalid LeftmostColumn '$($leftParts[1])'."
        }

        if (-not [int]::TryParse($rightParts[0], [ref]$rightmostLine)) {
            throw "Row $chainNumber has invalid RightmostLine '$($rightParts[0])'."
        }

        if (-not [int]::TryParse($rightParts[1], [ref]$rightmostColumn)) {
            throw "Row $chainNumber has invalid RightmostColumn '$($rightParts[1])'."
        }

        if ($leftmostLine -lt 1 -or $leftmostColumn -lt 1) {
            throw "Row $chainNumber has invalid leftmost source position."
        }

        if ($rightmostLine -lt 1 -or $rightmostColumn -lt 1) {
            throw "Row $chainNumber has invalid rightmost source position."
        }

        # --------------------------------------------------------------
        # Parse Methods.
        #
        # Example:
        #
        #     En_SelectMany -> En_Concat
        #
        # The prefix identifies the API:
        #
        #     En_ = Enumerable
        #     Qu_ = Queryable
        # --------------------------------------------------------------

        $methodNames = @(
            $methodsText -split '\s*->\s*'
        )

        if ($methodNames.Count -lt 2) {
            throw "Row $chainNumber ChainId '$chainId' contains fewer than two methods."
        }

        if ($methodNames.Count -gt 255) {
            throw "Row $chainNumber contains $($methodNames.Count) methods; ChainLength cannot exceed 255."
        }

        $chainLength = [byte]$methodNames.Count

        # --------------------------------------------------------------
        # Insert the Chain row.
        # --------------------------------------------------------------

        $chainCommand.Parameters["@Repository"].Value = $repository
        $chainCommand.Parameters["@CommitHash"].Value = $commitHash
        $chainCommand.Parameters["@ChainId"].Value = $chainId
        $chainCommand.Parameters["@Project"].Value = $project
        $chainCommand.Parameters["@LeftmostLine"].Value = $leftmostLine
        $chainCommand.Parameters["@LeftmostColumn"].Value = $leftmostColumn
        $chainCommand.Parameters["@RightmostLine"].Value = $rightmostLine
        $chainCommand.Parameters["@RightmostColumn"].Value = $rightmostColumn
        $chainCommand.Parameters["@ChainLength"].Value = $chainLength

        [void]$chainCommand.ExecuteNonQuery()

        # --------------------------------------------------------------
        # Resolve and insert each method.
        #
        # PositionInChain is deliberately 1-based.
        # --------------------------------------------------------------

        $positionInChain = 0

        foreach ($methodName in $methodNames) {

            $positionInChain++

            $methodName = ([string]$methodName).Trim()

            if ($methodName -notmatch '^(En|Qu)_(.+)$') {
                throw @"
Row $chainNumber contains an invalid LINQ method name '$methodName'.

Expected a name beginning with En_ or Qu_.
"@
            }

            $prefix = $Matches[1]
            $operator = $Matches[2]

            if ($prefix -eq 'En') {
                $api = 'Enumerable'
            }
            else {
                $api = 'Queryable'
            }

            if ([string]::IsNullOrWhiteSpace($operator)) {
                throw "Row $chainNumber contains an empty LINQ operator."
            }

            # ----------------------------------------------------------
            # Resolve (Api, Operator) -> Methods.Id.
            # ----------------------------------------------------------

            $methodCommand.Parameters["@Api"].Value = $api
            $methodCommand.Parameters["@Operator"].Value = $operator

            $methodIdObject = $methodCommand.ExecuteScalar()

            if ($null -eq $methodIdObject) {
                throw @"
Could not resolve LINQ method:

    Api:      $api
    Operator: $operator

from dbo.Methods.
"@
            }

            [int]$methodId = [int]$methodIdObject

            # ----------------------------------------------------------
            # Insert ChainMethods row.
            # ----------------------------------------------------------

            $chainMethodCommand.Parameters["@Repository"].Value = $repository
            $chainMethodCommand.Parameters["@CommitHash"].Value = $commitHash
            $chainMethodCommand.Parameters["@ChainId"].Value = $chainId
            $chainMethodCommand.Parameters["@PositionInChain"].Value =
                [byte]$positionInChain
            $chainMethodCommand.Parameters["@MethodId"].Value = $methodId

            [void]$chainMethodCommand.ExecuteNonQuery()
        }

        # This should always hold because PositionInChain starts at 1
        # and increments once for every method.
        if ($positionInChain -ne $chainLength) {
            throw "Internal error: ChainLength and PositionInChain count disagree for ChainId '$chainId'."
        }

        if (($chainNumber % 500) -eq 0) {
            Write-Host "Processed $chainNumber of $($chains.Count) chains..."
        }
    }

    # ------------------------------------------------------------------
    # Commit both tables atomically.
    # ------------------------------------------------------------------

    $transaction.Commit()

    Write-Host ""
    Write-Host "Chains and ChainMethods populated successfully."
    Write-Host "  Repository: $repository"
    Write-Host "  CommitHash: $commitHash"
    Write-Host "  Chains:     $($chains.Count)"
}
catch {
    $originalException = $_.Exception

    try {
        $transaction.Rollback()
    }
    catch {
        Write-Warning "Rollback failed: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-Host "Chains import failed. Transaction rolled back."
    Write-Host ""
    Write-Host "Original error:"
    Write-Host $originalException.ToString()

    throw $originalException
}
finally {

    if ($null -ne $methodCommand) {
        $methodCommand.Dispose()
    }

    if ($null -ne $chainCommand) {
        $chainCommand.Dispose()
    }

    if ($null -ne $chainMethodCommand) {
        $chainMethodCommand.Dispose()
    }

    if ($connection.State -ne [System.Data.ConnectionState]::Closed) {
        $connection.Close()
    }

    $connection.Dispose()
}