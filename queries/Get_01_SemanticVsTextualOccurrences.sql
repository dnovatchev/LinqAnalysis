/*
    Get_01_SemanticVsTextualOccurrences.sql

    TextualOccurrences:
        Number of rows in dbo.TextOccurrences.

    SemanticOccurrences:
        Number of rows in dbo.Occurrences where Kind = 'MethodCall'.

    TextualExcess:
        TextualOccurrences - SemanticOccurrences.

    TextualExcessOverSemanticPct:
        ((TextualOccurrences - SemanticOccurrences)
         / SemanticOccurrences) * 100

        Denominator: SemanticOccurrences.

    SemanticCountPortionOfTextualOccurrences:
        (SemanticOccurrences / TextualOccurrences) * 100

        Denominator: TextualOccurrences.
*/

WITH CorpusCounts AS
(
    SELECT
        cm.Repository,

        TextualOccurrences =
        (
            SELECT COUNT_BIG(*)
            FROM dbo.TextOccurrences AS t
            WHERE t.Repository = cm.Repository
              AND t.CommitHash = cm.CommitHash
        ),

        SemanticOccurrences =
        (
            SELECT COUNT_BIG(*)
            FROM dbo.Occurrences AS o
            WHERE o.Repository = cm.Repository
              AND o.CommitHash = cm.CommitHash
              AND o.Kind = 'MethodCall'
        )

    FROM dbo.CorpusMeasurement AS cm
),
Results AS
(
    SELECT
        Repository,
        TextualOccurrences,
        SemanticOccurrences,
        TextualOccurrences - SemanticOccurrences AS TextualExcess,

        CAST(
            100.0 * (TextualOccurrences - SemanticOccurrences)
            / NULLIF(SemanticOccurrences, 0)
            AS decimal(10, 2)
        ) AS TextualExcessOverSemanticPct,

        CAST(
            100.0 * SemanticOccurrences
            / NULLIF(TextualOccurrences, 0)
            AS decimal(10, 2)
        ) AS SemanticCountPortionOfTextualOccurrences

    FROM CorpusCounts

    UNION ALL

    SELECT
        'Total',
        SUM(TextualOccurrences),
        SUM(SemanticOccurrences),
        SUM(TextualOccurrences) - SUM(SemanticOccurrences),

        CAST(
            100.0 * (SUM(TextualOccurrences) - SUM(SemanticOccurrences))
            / NULLIF(SUM(SemanticOccurrences), 0)
            AS decimal(10, 2)
        ),

        CAST(
            100.0 * SUM(SemanticOccurrences)
            / NULLIF(SUM(TextualOccurrences), 0)
            AS decimal(10, 2)
        )

    FROM CorpusCounts
)
SELECT
    Repository,
    TextualOccurrences,
    SemanticOccurrences,
    TextualExcess,
    TextualExcessOverSemanticPct,
    SemanticCountPortionOfTextualOccurrences
FROM Results
ORDER BY
    CASE WHEN Repository = 'Total' THEN 1 ELSE 0 END,
    Repository;