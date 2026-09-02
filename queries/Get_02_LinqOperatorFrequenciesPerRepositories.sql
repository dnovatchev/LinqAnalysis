/*
    Get_02_LinqOperatorFrequencies.sql

    Reports the frequency of each LINQ operator, per repository,
    based on semantically verified LINQ method calls.

    OccurrenceCount:
        Number of semantic MethodCall occurrences for the
        Repository / Api / Operator combination.

    PercentageOfTotalOccurrences:
        OccurrenceCount / total semantic MethodCall occurrences
        for the repository * 100.

    Methods is the driving table so that operators with zero
    occurrences are included.

    The query is data-driven and does not contain repository names.
*/

WITH Repositories AS
(
    SELECT
        Repository,
        CommitHash
    FROM dbo.CorpusMeasurement
),
TotalOccurrences AS
(
    SELECT
        o.Repository,
        o.CommitHash,
        COUNT_BIG(*) AS TotalOccurrenceCount
    FROM dbo.Occurrences AS o
    WHERE o.Kind = 'MethodCall'
    GROUP BY
        o.Repository,
        o.CommitHash
),
OperatorFrequencies AS
(
    SELECT
        r.Repository,
        r.CommitHash,
        m.Api,
        m.Operator,
        COUNT_BIG(o.Operator) AS OccurrenceCount
    FROM Repositories AS r
    CROSS JOIN dbo.Methods AS m
    LEFT JOIN dbo.Occurrences AS o
        ON  o.Repository = r.Repository
        AND o.CommitHash = r.CommitHash
        AND o.Api = m.Api
        AND o.Operator = m.Operator
        AND o.Kind = 'MethodCall'
    GROUP BY
        r.Repository,
        r.CommitHash,
        m.Api,
        m.Operator
)
SELECT
    f.Repository,
    f.Api,
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
    f.Operator,
    f.Api;