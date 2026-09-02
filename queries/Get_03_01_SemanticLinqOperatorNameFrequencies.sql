/*
    Get_03_01_SemanticLinqOperatorNameFrequencies.sql

    Reports the frequency of each LINQ operator name, per repository,
    combining occurrences from Enumerable and Queryable.

    OccurrenceCount:
        Number of semantically verified LINQ MethodCall occurrences
        for the Repository / Operator combination.

    PercentageOfTotalOccurrences:
        OccurrenceCount / total semantic MethodCall occurrences
        for the repository * 100.
*/

WITH TotalOccurrences AS
(
    SELECT
        Repository,
        CommitHash,
        COUNT_BIG(*) AS TotalOccurrenceCount
    FROM dbo.Occurrences
    WHERE Kind = 'MethodCall'
    GROUP BY
        Repository,
        CommitHash
),
OperatorFrequencies AS
(
    SELECT
        Repository,
        CommitHash,
        Operator,
        COUNT_BIG(*) AS OccurrenceCount
    FROM dbo.Occurrences
    WHERE Kind = 'MethodCall'
    GROUP BY
        Repository,
        CommitHash,
        Operator
)
SELECT
    f.Repository,
    f.Operator,
    f.OccurrenceCount,
    CAST(
        100.0 * f.OccurrenceCount
        / NULLIF(t.TotalOccurrenceCount, 0)
        AS decimal(10, 2)
    ) AS PercentageOfTotalOccurrences
FROM OperatorFrequencies AS f
LEFT JOIN TotalOccurrences AS t
    ON  t.Repository = f.Repository
    AND t.CommitHash = f.CommitHash
ORDER BY
    f.Repository,
    f.OccurrenceCount DESC,
    f.Operator;