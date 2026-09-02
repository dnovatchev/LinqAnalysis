# ============================================================
# RunCorpusAnalysis.ps1
#
# Corpus-specific procedure:
#
#   1. Determine the corpus Git HEAD.
#   2. If env-corpus.json exists and its Git hash matches:
#        reconstruct the saved build environment.
#   3. Otherwise:
#        perform a full corpus build,
#        capture the resulting environment,
#        save env-corpus.json.
#   4. Run the LINQ semantic analyzer.
#   5. Run the LINQ textual analyzer against exactly the
#      processed-files.txt produced by the semantic analyzer.
# The corpus is NOT rebuilt when the Git revision has not changed.
# Textual analysis is performed only after successful semantic
# analysis and uses the semantic analyzer's processed-files.txt.
# ============================================================

param(
    [Parameter(Mandatory = $true)]
    [string]$CorpusRoot
)

$ErrorActionPreference = "Stop"

# ============================================================
# Resolve paths
# ============================================================

$CorpusRoot = (Resolve-Path $CorpusRoot).Path
$RepositoryName = Split-Path $CorpusRoot -Leaf

$AnalyzerRoot = Split-Path $PSScriptRoot -Parent

$AnalyzerExe =
    Join-Path $AnalyzerRoot "Analyzer\bin\Debug\net9.0\LinqCorpusAnalyzer.exe"

$TextAnalyzerExe =
Join-Path $AnalyzerRoot `
    "LinqCorpusTextAnalyzer\bin\Debug\net9.0\LinqCorpusTextAnalyzer.exe"

$EnvironmentFile =
    Join-Path $CorpusRoot "env-corpus.json"

$SolutionFile =
    Join-Path $CorpusRoot "$RepositoryName.sln"

# ============================================================
# Header
# ============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host "LINQ CORPUS ANALYSIS"
Write-Host "============================================================"
Write-Host "Repository: $RepositoryName"
Write-Host "Path:       $CorpusRoot"
Write-Host ""

# ============================================================
# Validate analyzer
# ============================================================

if (-not (Test-Path $AnalyzerExe)) {
    throw "Analyzer executable not found: $AnalyzerExe"
}

if (-not (Test-Path $TextAnalyzerExe)) {
    throw "Textual analyzer executable not found: $TextAnalyzerExe"
}

# ============================================================
# Determine Git HEAD
# ============================================================

$GitHash = (
    git -C $CorpusRoot rev-parse HEAD
).Trim()

if ($LASTEXITCODE -ne 0 -or
    [string]::IsNullOrWhiteSpace($GitHash)) {

    throw "Could not determine Git HEAD for corpus: $CorpusRoot"
}

Write-Host "Git HEAD:   $GitHash"
Write-Host ""

# ============================================================
# Functions
# ============================================================

function Get-CurrentCorpusEnvironment {

    $dotnetCommand = Get-Command dotnet -ErrorAction Stop

    [PSCustomObject]@{
        GitHash                 = $GitHash

        DOTNET_ROOT             = $env:DOTNET_ROOT
        DOTNET_ROOT_x64         = $env:DOTNET_ROOT_x64
        DOTNET_INSTALL_DIR      = $env:DOTNET_INSTALL_DIR

        PATH                    = $env:PATH

        NUGET_PACKAGES          = $env:NUGET_PACKAGES
        NUGET_HTTP_CACHE_PATH   = $env:NUGET_HTTP_CACHE_PATH
        NUGET_PLUGINS_CACHE_PATH = $env:NUGET_PLUGINS_CACHE_PATH

        DOTNET_EXE              = $dotnetCommand.Source
    }
}


function Restore-CorpusEnvironment {

    param(
        [Parameter(Mandatory = $true)]
        $Environment
    )

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "RESTORING SAVED CORPUS ENVIRONMENT"
    Write-Host "============================================================"

    $env:DOTNET_ROOT =
        $Environment.DOTNET_ROOT

    $env:DOTNET_ROOT_x64 =
        $Environment.DOTNET_ROOT_x64

    $env:DOTNET_INSTALL_DIR =
        $Environment.DOTNET_INSTALL_DIR

    $env:PATH =
        $Environment.PATH

    $env:NUGET_PACKAGES =
        $Environment.NUGET_PACKAGES

    $env:NUGET_HTTP_CACHE_PATH =
        $Environment.NUGET_HTTP_CACHE_PATH

    $env:NUGET_PLUGINS_CACHE_PATH =
        $Environment.NUGET_PLUGINS_CACHE_PATH

    Write-Host "Saved Git hash:"
    Write-Host "  $($Environment.GitHash)"

    Write-Host ""
    Write-Host "Saved dotnet:"
    Write-Host "  $($Environment.DOTNET_EXE)"

    Write-Host ""
    Write-Host "Effective dotnet after restoration:"

    $dotnet = Get-Command dotnet -ErrorAction Stop

    Write-Host "  $($dotnet.Source)"

    if ($dotnet.Source -ne $Environment.DOTNET_EXE) {

        throw (
            "Restored environment does not resolve dotnet.exe " +
            "to the saved executable.`n" +
            "Expected: $($Environment.DOTNET_EXE)`n" +
            "Actual:   $($dotnet.Source)"
        )
    }

    Write-Host ""
    Write-Host "Environment successfully restored."
}


function Save-CorpusEnvironment {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $environment =
        Get-CurrentCorpusEnvironment

    $json =
        $environment |
        ConvertTo-Json -Depth 5

    $json |
        Set-Content `
            -Path $Path `
            -Encoding UTF8

    Write-Host ""
    Write-Host "Corpus environment saved:"
    Write-Host "  $Path"

    Write-Host ""
    Write-Host "Effective .NET environment:"
    Write-Host ""

    Get-Command dotnet |
        Select-Object Source |
        Format-Table

    Write-Host "DOTNET_ROOT:        $env:DOTNET_ROOT"
    Write-Host "DOTNET_INSTALL_DIR: $env:DOTNET_INSTALL_DIR"
}


function Test-SavedEnvironment {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$CurrentGitHash
    )

    if (-not (Test-Path $Path)) {
        return $false
    }

    try {

        $saved =
            Get-Content $Path -Raw |
            ConvertFrom-Json

    }
    catch {

        Write-Host ""
        Write-Host "WARNING: Could not read $Path"
        Write-Host "A full corpus build will be performed."

        return $false
    }

    if ([string]::IsNullOrWhiteSpace($saved.GitHash)) {

        Write-Host ""
        Write-Host "WARNING: Saved corpus environment has no Git hash."
        Write-Host "A full corpus build will be performed."

        return $false
    }

    if ($saved.GitHash -ne $CurrentGitHash) {

        Write-Host ""
        Write-Host "Saved corpus environment belongs to another Git revision."
        Write-Host "Saved:   $($saved.GitHash)"
        Write-Host "Current: $CurrentGitHash"
        Write-Host ""
        Write-Host "A full corpus build is required."

        return $false
    }

    return $true
}

# ============================================================
# STEP 1: Corpus build environment
# ============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host "STEP 1: CORPUS BUILD ENVIRONMENT"
Write-Host "============================================================"

$environmentRestored = $false

if (Test-SavedEnvironment `
        -Path $EnvironmentFile `
        -CurrentGitHash $GitHash) {

    Write-Host ""
    Write-Host "Saved corpus environment found:"
    Write-Host "  $EnvironmentFile"

    $savedEnvironment =
        Get-Content $EnvironmentFile -Raw |
        ConvertFrom-Json

    Restore-CorpusEnvironment `
        -Environment $savedEnvironment

    $environmentRestored = $true
}
else {

    if (-not (Test-Path $EnvironmentFile)) {

        Write-Host ""
        Write-Host "No saved corpus environment found."
        Write-Host "A full corpus build is required."
    }

    Write-Host ""
Write-Host ""
Write-Host "Performing full corpus build:"
Write-Host ""

Push-Location $CorpusRoot

try {

if ($RepositoryName -eq "dotnet-runtime") {

    Write-Host "  .\eng\common\build.ps1 -restore"
    Write-Host ""

    & .\eng\common\build.ps1 -restore

    if ($LASTEXITCODE -ne 0) {

        throw (
            "$RepositoryName restore failed " +
            "with exit code $LASTEXITCODE."
        )
    }

    $reuse = $false

    Write-Host ""
    Write-Host "  .\eng\common\build.ps1 -build -nodeReuse `$false"
    Write-Host ""

    & .\eng\common\build.ps1 `
        -build `
        -nodeReuse $reuse

    if ($LASTEXITCODE -ne 0) {

        throw (
            "$RepositoryName build failed " +
            "with exit code $LASTEXITCODE."
        )
    }
}
elseif ($RepositoryName -eq "dotnet-efcore") {

    Write-Host "  .\eng\common\build.ps1 -restore"
    Write-Host ""

    & .\eng\common\build.ps1 -restore

    if ($LASTEXITCODE -ne 0) {

        throw (
            "$RepositoryName restore failed " +
            "with exit code $LASTEXITCODE."
        )
    }

    $reuse = $false

    Write-Host ""
    Write-Host "  .\eng\common\build.ps1 -build -nodeReuse `$false"
    Write-Host ""

    & .\eng\common\build.ps1 `
        -build `
        -nodeReuse $reuse

    if ($LASTEXITCODE -ne 0) {

        throw (
            "$RepositoryName build failed " +
            "with exit code $LASTEXITCODE."
        )
    }
}
else {

    Write-Host "  dotnet build $SolutionFile"
    Write-Host ""

    & dotnet build $SolutionFile

    if ($LASTEXITCODE -ne 0) {

        throw (
            "$RepositoryName build failed " +
            "with exit code $LASTEXITCODE."
        )
    }
}

}
finally {

    Pop-Location
}

Write-Host ""
Write-Host "Corpus build succeeded."

    # Capture the environment that successfully built
    # this exact Git revision.
    Save-CorpusEnvironment `
        -Path $EnvironmentFile
}

# ============================================================
# Final environment verification
# ============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host "VERIFYING CORPUS ENVIRONMENT"
Write-Host "============================================================"

$currentDotnet =
    (Get-Command dotnet -ErrorAction Stop).Source

Write-Host "Git HEAD:"
Write-Host "  $GitHash"

Write-Host ""
Write-Host "dotnet:"
Write-Host "  $currentDotnet"

Write-Host ""
Write-Host "DOTNET_ROOT:"
Write-Host "  $env:DOTNET_ROOT"

Write-Host ""
Write-Host "DOTNET_INSTALL_DIR:"
Write-Host "  $env:DOTNET_INSTALL_DIR"

# If we restored an environment, make sure the exact
# saved dotnet executable is still being used.
if ($environmentRestored) {

    if ($currentDotnet -ne $savedEnvironment.DOTNET_EXE) {

        throw (
            "Corpus environment verification failed.`n" +
            "Saved dotnet:   $($savedEnvironment.DOTNET_EXE)`n" +
            "Current dotnet: $currentDotnet"
        )
    }

    Write-Host ""
    Write-Host "Saved corpus environment verified."
}

# ============================================================
# STEP 2: Run semantic analyzer
# ============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host "STEP 2: RUN LINQ CORPUS ANALYZER"
Write-Host "============================================================"

Write-Host ""
Write-Host "Analyzer:"
Write-Host "  $AnalyzerExe"

Write-Host ""
Write-Host "Repository:"
Write-Host "  $CorpusRoot"

Write-Host ""

& $AnalyzerExe $CorpusRoot

if ($LASTEXITCODE -ne 0) {

    throw (
        "LINQ corpus analyzer failed " +
        "with exit code $LASTEXITCODE."
    )
}

# ============================================================
# STEP 3: Run textual analyzer
#
# The textual analyzer MUST consume the exact
# processed-files.txt produced by the semantic analyzer.
# Therefore it is run only after a successful semantic run.
# ============================================================

$ResultsDirectory =
    Join-Path `
        $AnalyzerRoot `
        "Analyzer\Results\$RepositoryName"

$ProcessedFilesPath =
    Join-Path `
        $ResultsDirectory `
        "processed-files.txt"

if (-not (Test-Path $ProcessedFilesPath)) {

    throw (
        "Semantic analyzer succeeded but did not produce " +
        "processed-files.txt.`n" +
        "Expected: $ProcessedFilesPath"
    )
}

Write-Host ""
Write-Host "============================================================"
Write-Host "STEP 3: RUN LINQ TEXTUAL ANALYZER"
Write-Host "============================================================"

Write-Host ""
Write-Host "Textual analyzer:"
Write-Host "  $TextAnalyzerExe"

Write-Host ""
Write-Host "Repository:"
Write-Host "  $CorpusRoot"

Write-Host ""
Write-Host "Processed-files list:"
Write-Host "  $ProcessedFilesPath"

Write-Host ""

& $TextAnalyzerExe `
    $CorpusRoot `
    $ProcessedFilesPath

if ($LASTEXITCODE -ne 0) {

    throw (
        "LINQ textual analyzer failed " +
        "with exit code $LASTEXITCODE."
    )
}

Write-Host ""
Write-Host "============================================================"
Write-Host "CORPUS ANALYSIS COMPLETED SUCCESSFULLY"
Write-Host "============================================================"
