# ============================================================
# CompareTextualSemantic.ps1
#
# Compare textual and semantic LINQ occurrences PER FILE.
#
# The semantic analyzer's QuerySyntax occurrences are excluded.
# We compare only semantic MethodCall occurrences against the
# textual analyzer's member-name occurrences.
#
# Outputs:
#
#   textual-semantic-per-file.csv
#       One row per physical file.
#
#   textual-semantic-per-file-member.csv
#       Detailed member-level differences for files where
#       textual and semantic counts differ.
#
# The console output contains only aggregate results.
# ============================================================

param(
    [Parameter(Mandatory = $true)]
    [string]$ResultsDirectory
)

$ErrorActionPreference = "Stop"

$ResultsDirectory =
    (Resolve-Path $ResultsDirectory).Path

$SemanticPath =
    Join-Path $ResultsDirectory "occurrences.csv"

$TextualPath =
    Join-Path $ResultsDirectory "text-occurrences.csv"

if (-not (Test-Path $SemanticPath)) {
    throw "Semantic occurrences file not found: $SemanticPath"
}

if (-not (Test-Path $TextualPath)) {
    throw "Textual occurrences file not found: $TextualPath"
}

Write-Host ""
Write-Host "============================================================"
Write-Host "TEXTUAL vs SEMANTIC LINQ OCCURRENCES"
Write-Host "============================================================"
Write-Host "Results directory:"
Write-Host "  $ResultsDirectory"
Write-Host ""

# ============================================================
# Read semantic occurrences
# ============================================================

$semanticAll =
    Import-Csv $SemanticPath

$semantic =
    $semanticAll |
    Where-Object {
        $_.Kind -eq "MethodCall"
    }

$querySyntax =
    $semanticAll |
    Where-Object {
        $_.Kind -eq "QuerySyntax"
    }

# ============================================================
# Read textual occurrences
# ============================================================

$textual =
    Import-Csv $TextualPath

Write-Host "Semantic MethodCall occurrences: $($semantic.Count)"
Write-Host "Semantic QuerySyntax occurrences: $($querySyntax.Count)"
Write-Host "Textual occurrences:             $($textual.Count)"
Write-Host ""

# ============================================================
# Normalize paths ONCE
#
# Avoid repeatedly calling GetFullPath() inside large loops.
# ============================================================

foreach ($x in $semantic) {
    $x | Add-Member -NotePropertyName NormalizedFile -NotePropertyValue (
        [System.IO.Path]::GetFullPath($x.File)
    )
}

foreach ($x in $textual) {
    $x | Add-Member -NotePropertyName NormalizedFile -NotePropertyValue (
        [System.IO.Path]::GetFullPath($x.File)
    )
}

# ============================================================
# Group occurrences by file
# ============================================================

$semanticByFile =
    $semantic |
    Group-Object NormalizedFile

$textualByFile =
    $textual |
    Group-Object NormalizedFile

# Create dictionaries for O(1) lookup by file.
$semanticFileMap = @{}
foreach ($group in $semanticByFile) {
    $semanticFileMap[$group.Name] = $group.Group
}

$textualFileMap = @{}
foreach ($group in $textualByFile) {
    $textualFileMap[$group.Name] = $group.Group
}

# ============================================================
# Build complete set of files
# ============================================================

$allFiles =
    @(
        $semanticFileMap.Keys
        $textualFileMap.Keys
    ) |
    Sort-Object -Unique

# ============================================================
# Per-file comparison
# ============================================================

$comparison =
    foreach ($file in $allFiles) {

        $semanticGroup =
            if ($semanticFileMap.ContainsKey($file)) {
                $semanticFileMap[$file]
            }
            else {
                @()
            }

        $textualGroup =
            if ($textualFileMap.ContainsKey($file)) {
                $textualFileMap[$file]
            }
            else {
                @()
            }

        $semanticCount = @($semanticGroup).Count
        $textualCount  = @($textualGroup).Count

        [PSCustomObject]@{
            File       = $file
            Textual    = $textualCount
            Semantic   = $semanticCount
            Difference = $textualCount - $semanticCount
        }
    }

# ============================================================
# Summary
# ============================================================

$equal =
    @($comparison | Where-Object Difference -eq 0)

$over =
    @($comparison |
        Where-Object Difference -gt 0 |
        Sort-Object Difference -Descending)

$under =
    @($comparison |
        Where-Object Difference -lt 0 |
        Sort-Object Difference)

$zero =
    @($comparison |
        Where-Object {
            $_.Textual -eq 0 -and
            $_.Semantic -eq 0
        })

Write-Host ""
Write-Host "============================================================"
Write-Host "PER-FILE SUMMARY"
Write-Host "============================================================"

Write-Host ""
Write-Host "Files occurring in either result:"
Write-Host "  $($comparison.Count)"

Write-Host ""
Write-Host "Textual = Semantic:"
Write-Host "  $($equal.Count)"

Write-Host ""
Write-Host "Textual > Semantic:"
Write-Host "  $($over.Count)"

Write-Host ""
Write-Host "Textual < Semantic:"
Write-Host "  $($under.Count)"

Write-Host ""
Write-Host "Both zero:"
Write-Host "  $($zero.Count)"

# ============================================================
# Total accounting
# ============================================================

$totalTextual =
    [int](($comparison | Measure-Object Textual -Sum).Sum)

$totalSemantic =
    [int](($comparison | Measure-Object Semantic -Sum).Sum)

$totalDifference =
    [int](($comparison | Measure-Object Difference -Sum).Sum)

Write-Host ""
Write-Host "============================================================"
Write-Host "TOTAL ACCOUNTING"
Write-Host "============================================================"

Write-Host ""
Write-Host "Textual total:       $totalTextual"
Write-Host "Semantic total:      $totalSemantic"
Write-Host "Textual - Semantic:  $totalDifference"

# ============================================================
# Sanity check
# ============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host "SANITY CHECK"
Write-Host "============================================================"

if ($under.Count -eq 0) {

    Write-Host ""
    Write-Host "PASS: No file has Textual < Semantic."
}
else {

    Write-Host ""
    Write-Host "WARNING: $($under.Count) files have Textual < Semantic."
    Write-Host ""
    Write-Host "Largest discrepancies:"
    Write-Host ""

    $under |
        Select-Object -First 20 |
        Format-Table `
            @{Label="Difference";Expression={$_.Difference}},
            @{Label="Textual";Expression={$_.Textual}},
            @{Label="Semantic";Expression={$_.Semantic}},
            @{Label="File";Expression={$_.File}} `
            -AutoSize
}

# ============================================================
# Operator-level comparison
#
# This is the main aggregate comparison used by the study.
# ============================================================

$semanticByOperator =
    $semantic |
    Group-Object Operator

$textualByOperator =
    $textual |
    Group-Object Operator

$semanticOperatorMap = @{}
foreach ($group in $semanticByOperator) {
    $semanticOperatorMap[$group.Name] = $group.Count
}

$textualOperatorMap = @{}
foreach ($group in $textualByOperator) {
    $textualOperatorMap[$group.Name] = $group.Count
}

$allOperators =
    @(
        $semanticOperatorMap.Keys
        $textualOperatorMap.Keys
    ) |
    Sort-Object -Unique

$operatorComparison =
    foreach ($operator in $allOperators) {

        $s =
            if ($semanticOperatorMap.ContainsKey($operator)) {
                $semanticOperatorMap[$operator]
            }
            else {
                0
            }

        $t =
            if ($textualOperatorMap.ContainsKey($operator)) {
                $textualOperatorMap[$operator]
            }
            else {
                0
            }

        $precision =
            if ($t -eq 0) {
                $null
            }
            else {
                [math]::Round(
                    100.0 * $s / $t,
                    2
                )
            }

        [PSCustomObject]@{
            Operator  = $operator
            Textual   = $t
            Semantic  = $s
            Precision = $precision
            Difference = $t - $s
        }
    }

Write-Host ""
Write-Host "============================================================"
Write-Host "OPERATOR COMPARISON"
Write-Host "============================================================"
Write-Host ""

$operatorComparison |
    Sort-Object Textual -Descending |
    Format-Table `
        Operator,
        Textual,
        Semantic,
        Precision,
        Difference `
        -AutoSize

# ============================================================
# Member-level analysis
#
# IMPORTANT:
# Do not print 21,000+ files.
#
# Save only member-level differences to CSV.
# ============================================================

$memberComparison =
    foreach ($file in $allFiles) {

        $semanticGroup =
            if ($semanticFileMap.ContainsKey($file)) {
                $semanticFileMap[$file]
            }
            else {
                @()
            }

        $textualGroup =
            if ($textualFileMap.ContainsKey($file)) {
                $textualFileMap[$file]
            }
            else {
                @()
            }

        $semanticMembers =
            $semanticGroup |
            Group-Object Operator

        $textualMembers =
            $textualGroup |
            Group-Object Operator

        $semanticMemberMap = @{}
        foreach ($group in $semanticMembers) {
            $semanticMemberMap[$group.Name] = $group.Count
        }

        $textualMemberMap = @{}
        foreach ($group in $textualMembers) {
            $textualMemberMap[$group.Name] = $group.Count
        }

        $members =
            @(
                $semanticMemberMap.Keys
                $textualMemberMap.Keys
            ) |
            Sort-Object -Unique

        foreach ($member in $members) {

            $s =
                if ($semanticMemberMap.ContainsKey($member)) {
                    $semanticMemberMap[$member]
                }
                else {
                    0
                }

            $t =
                if ($textualMemberMap.ContainsKey($member)) {
                    $textualMemberMap[$member]
                }
                else {
                    0
                }

            $difference = $t - $s

            if ($difference -ne 0) {

                [PSCustomObject]@{
                    File       = $file
                    Operator   = $member
                    Textual    = $t
                    Semantic   = $s
                    Difference = $difference
                }
            }
        }
    }

# ============================================================
# Save complete per-file comparison
# ============================================================

$comparisonPath =
    Join-Path `
        $ResultsDirectory `
        "textual-semantic-per-file.csv"

$comparison |
    Sort-Object File |
    Export-Csv `
        -Path $comparisonPath `
        -NoTypeInformation `
        -Encoding UTF8

# ============================================================
# Save member-level differences
# ============================================================

$memberComparisonPath =
    Join-Path `
        $ResultsDirectory `
        "textual-semantic-per-file-member.csv"

$memberComparison |
    Sort-Object File, Operator |
    Export-Csv `
        -Path $memberComparisonPath `
        -NoTypeInformation `
        -Encoding UTF8

# ============================================================
# Final output
# ============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host "COMPARISON SAVED"
Write-Host "============================================================"

Write-Host ""
Write-Host "Per-file comparison:"
Write-Host "  $comparisonPath"

Write-Host ""
Write-Host "Per-file/member differences:"
Write-Host "  $memberComparisonPath"

Write-Host ""