$ErrorActionPreference = "Stop"

$Root = "C:\LinqCorpus"
$OutputFile = Join-Path $Root "CorpusMeasurement.csv"

# Safety check: the expected corpus directory must exist.
if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    throw "The directory '$Root' does not exist."
}

Write-Host ""
Write-Host "LINQ corpus measurement" -ForegroundColor Cyan
Write-Host "Root: $Root"
Write-Host "Output: $OutputFile"
Write-Host ""

# Directories that are not part of the source corpus.
$ExcludedDirectoryNames = @(
    ".git",
    "bin",
    "obj"
)

# These directory names are useful for classification,
# but are NOT excluded from the basic C# measurement.
$TestDirectoryNames = @(
    "test",
    "tests"
)

$BenchmarkDirectoryNames = @(
    "benchmark",
    "benchmarks"
)

$results = @()

# Only examine directories immediately under C:\LinqCorpus.
$Repositories = Get-ChildItem `
    -LiteralPath $Root `
    -Directory `
    -Force |
    Where-Object {
        $_.Name -notin @(
            ".git"
        )
    } |
    Sort-Object Name

foreach ($Repository in $Repositories) {

    Write-Host "Measuring: $($Repository.Name)" -ForegroundColor Yellow

    $TotalFiles = 0
    $CSharpFiles = 0
    $CSharpBytes = [int64]0
    $CSharpLines = [int64]0

    $CSharpTestFiles = 0
    $CSharpTestBytes = [int64]0
    $CSharpTestLines = [int64]0

    $CSharpBenchmarkFiles = 0
    $CSharpBenchmarkBytes = [int64]0
    $CSharpBenchmarkLines = [int64]0

    $CsprojFiles = 0

    # Get all files, while pruning excluded directories.
    $Files = Get-ChildItem `
        -LiteralPath $Repository.FullName `
        -File `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $relativePath = $_.FullName.Substring(
                $Repository.FullName.Length
            ).TrimStart('\')

            $parts = $relativePath -split '\\'

            # Exclude .git, bin and obj anywhere in the path.
            -not ($parts | Where-Object {
                $_ -in $ExcludedDirectoryNames
            })
        }

    foreach ($File in $Files) {

        $TotalFiles++

        $extension = $File.Extension.ToLowerInvariant()

        if ($extension -eq ".csproj") {
            $CsprojFiles++
        }

        if ($extension -ne ".cs") {
            continue
        }

        $CSharpFiles++
        $CSharpBytes += $File.Length

        # Determine whether this file is under a test or benchmark directory.
        $relativePath = $File.FullName.Substring(
            $Repository.FullName.Length
        ).TrimStart('\')

        $parts = $relativePath -split '\\'

        $IsTest = $false
        $IsBenchmark = $false

        foreach ($part in $parts) {
            $lowerPart = $part.ToLowerInvariant()

            if ($lowerPart -in $TestDirectoryNames) {
                $IsTest = $true
            }

            if ($lowerPart -in $BenchmarkDirectoryNames) {
                $IsBenchmark = $true
            }
        }

        # Count physical lines.
        #
        # This is deliberately a simple physical-line measurement.
        # It is NOT intended to measure logical C# statements.
        try {
            $lineCount = 0

            $reader = [System.IO.StreamReader]::new(
                $File.FullName,
                [System.Text.Encoding]::UTF8,
                $true
            )

            try {
                while ($null -ne $reader.ReadLine()) {
                    $lineCount++
                }
            }
            finally {
                $reader.Dispose()
            }

            $CSharpLines += $lineCount

            if ($IsTest) {
                $CSharpTestFiles++
                $CSharpTestBytes += $File.Length
                $CSharpTestLines += $lineCount
            }

            if ($IsBenchmark) {
                $CSharpBenchmarkFiles++
                $CSharpBenchmarkBytes += $File.Length
                $CSharpBenchmarkLines += $lineCount
            }
        }
        catch {
            Write-Warning "Could not read '$($File.FullName)': $($_.Exception.Message)"
        }
    }

    $results += [PSCustomObject]@{
        Repository             = $Repository.Name
        TotalFiles             = $TotalFiles
        CsprojFiles            = $CsprojFiles
        CSharpFiles            = $CSharpFiles
        CSharpBytes            = $CSharpBytes
        CSharpMB               = [math]::Round(
            $CSharpBytes / 1MB, 2
        )
        CSharpLines            = $CSharpLines

        TestCSharpFiles        = $CSharpTestFiles
        TestCSharpMB           = [math]::Round(
            $CSharpTestBytes / 1MB, 2
        )
        TestCSharpLines        = $CSharpTestLines

        BenchmarkCSharpFiles   = $CSharpBenchmarkFiles
        BenchmarkCSharpMB      = [math]::Round(
            $CSharpBenchmarkBytes / 1MB, 2
        )
        BenchmarkCSharpLines   = $CSharpBenchmarkLines
    }

    Write-Host "  C# files: $CSharpFiles"
    Write-Host "  C# LOC:   $CSharpLines"
    Write-Host ""
}

# Write the results.
$results |
    Export-Csv `
        -LiteralPath $OutputFile `
        -NoTypeInformation `
        -Encoding UTF8

Write-Host "Measurement completed." -ForegroundColor Green
Write-Host ""
Write-Host "Results:"
$results | Format-Table -AutoSize

Write-Host ""
Write-Host "CSV written to:"
Write-Host $OutputFile
