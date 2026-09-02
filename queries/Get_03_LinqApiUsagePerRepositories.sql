/*
    Get_03_LinqApiUsagePerRepositories.sql

    Reports the composition of semantic LINQ method-call usage
    between System.Linq.Enumerable and System.Linq.Queryable,
    separately for each repository.

    OccurrenceCount:
        Number of semantic MethodCall occurrences for the
        Repository / Api combination.

    PercentageOfTotalOccurrences:
        OccurrenceCount / total semantic MethodCall occurrences
        for the repository * 100.

    QuerySyntax occurrences are excluded because only
    Kind = 'MethodCall' is counted.

    Repository names are not hardcoded.
*/

WITH ApiFrequencies AS
(
    SELECT
        o.Repository,
        o.CommitHash,
        o.Api,
        COUNT_BIG(*) AS OccurrenceCount
    FROM dbo.Occurrences AS o
    WHERE o.Kind = 'MethodCall'
    GROUP BY
        o.Repository,
        o.CommitHash,
        o.Api
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
)
SELECT
    f.Repository,
    f.Api,
    f.OccurrenceCount,

    CAST(
        100.0 * f.OccurrenceCount
        / NULLIF(t.TotalOccurrenceCount, 0)
        AS decimal(10, 2)
    ) AS PercentageOfTotalOccurrences

FROM ApiFrequencies AS f
INNER JOIN TotalOccurrences AS t
    ON  t.Repository = f.Repository
    AND t.CommitHash = f.CommitHash

ORDER BY
    f.Repository,
    f.OccurrenceCount DESC,
    f.Api;