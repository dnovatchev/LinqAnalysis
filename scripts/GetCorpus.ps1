$ErrorActionPreference = "Stop"

$Root = "C:\LinqCorpus"

# Safety check: work only inside the explicitly designated corpus directory.
if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    throw "The directory '$Root' does not exist."
}

$Repositories = @(
    @{
        Name = "dotnet-runtime"
        Url  = "https://github.com/dotnet/runtime.git"
    },
    @{
        Name = "dotnet-aspnetcore"
        Url  = "https://github.com/dotnet/aspnetcore.git"
    },
    @{
        Name = "dotnet-roslyn"
        Url  = "https://github.com/dotnet/roslyn.git"
    },
    @{
        Name = "dotnet-efcore"
        Url  = "https://github.com/dotnet/efcore.git"
    },
    @{
        Name = "nopCommerce"
        Url  = "https://github.com/nopSolutions/nopCommerce.git"
    },
    @{
        Name = "OrchardCore"
        Url  = "https://github.com/OrchardCMS/OrchardCore.git"
    },
    @{
        Name = "Avalonia"
        Url  = "https://github.com/AvaloniaUI/Avalonia.git"
    },
    @{
        Name = "PowerShell"
        Url  = "https://github.com/PowerShell/PowerShell.git"
    },
    @{
        Name = "serilog"
        Url  = "https://github.com/serilog/serilog.git"
    },
    @{
        Name = "Newtonsoft.Json"
        Url  = "https://github.com/JamesNK/Newtonsoft.Json.git"
    }
)

Write-Host ""
Write-Host "LINQ corpus acquisition" -ForegroundColor Cyan
Write-Host "Working directory: $Root"
Write-Host ""

# Verify that Git is available.
$Git = Get-Command git -ErrorAction SilentlyContinue

if ($null -eq $Git) {
    throw "Git was not found in PATH. Please install Git before running this script."
}

foreach ($Repository in $Repositories) {

    $Target = Join-Path $Root $Repository.Name

    Write-Host "Repository: $($Repository.Name)"

    if (Test-Path -LiteralPath $Target) {
        Write-Host "  Already exists - skipping clone." -ForegroundColor Yellow
        continue
    }

    Write-Host "  Cloning from $($Repository.Url)"

    # The only operation performed outside PowerShell itself:
    # Git downloads this explicitly specified public repository.
    & git clone --quiet -- $Repository.Url $Target

    if ($LASTEXITCODE -ne 0) {
        throw "Git failed while cloning '$($Repository.Url)'."
    }

    Write-Host "  Clone completed." -ForegroundColor Green
}

Write-Host ""
Write-Host "Corpus acquisition completed." -ForegroundColor Green
Write-Host "Repositories are located under: $Root"
Write-Host ""
