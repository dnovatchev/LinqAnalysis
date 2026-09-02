/*
    Get_08_03_CrossCorpus_LinqApiUsage.sql

    Compare the usage of the two LINQ APIs
    (Enumerable and Queryable) across repositories.

    An additional ALL_REPOSITORIES row is reported for each API.

    Each percentage is:

        API occurrence count
        --------------------- × 100
        total LINQ method occurrences in all applicable repositories

    Only semantic LINQ method calls are included:
        Occurrences.Kind = 'MethodCall'

    QuerySyntax occurrences are deliberately excluded because this query
    measures LINQ API usage, not query-syntax usage.

    Repository rows are listed first.

    ALL_REPOSITORIES rows are listed last, ranked by descending
    corpus-wide percentage.
*/

WITH ApiCounts AS
(
    SELECT
        o.Repository,
        o.Api,
        COUNT_BIG(*) AS OccurrenceCount
    FROM dbo.Occurrences AS o
    WHERE o.Kind = 'MethodCall'
    GROUP BY
        o.Repository,
        o.Api
),
RepositoryTotals AS
(
    SELECT
        Repository,
        SUM(OccurrenceCount)
            AS TotalRepositoryLinqMethodOccurrences
    FROM ApiCounts
    GROUP BY
        Repository
),
RepositoryResults AS
(
    SELECT
        a.Repository,
        a.Api,
        a.OccurrenceCount,
        t.TotalRepositoryLinqMethodOccurrences
    FROM ApiCounts AS a
    INNER JOIN RepositoryTotals AS t
        ON t.Repository = a.Repository
),
AllRepositoryTotal AS
(
    SELECT
        SUM(TotalRepositoryLinqMethodOccurrences)
            AS TotalAllRepositoryLinqMethodOccurrences
    FROM RepositoryTotals
),
AllRepositoryResults AS
(
    SELECT
        'ALL_REPOSITORIES' AS Repository,
        rr.Api,
        SUM(rr.OccurrenceCount) AS OccurrenceCount,
        art.TotalAllRepositoryLinqMethodOccurrences
            AS TotalRepositoryLinqMethodOccurrences
    FROM RepositoryResults AS rr
    CROSS JOIN AllRepositoryTotal AS art
    GROUP BY
        rr.Api,
        art.TotalAllRepositoryLinqMethodOccurrences
),
CombinedResults AS
(
    SELECT
        Repository,
        Api,
        OccurrenceCount,
        TotalRepositoryLinqMethodOccurrences,
        0 AS RepositorySortOrder
    FROM RepositoryResults

    UNION ALL

    SELECT
        Repository,
        Api,
        OccurrenceCount,
        TotalRepositoryLinqMethodOccurrences,
        1 AS RepositorySortOrder
    FROM AllRepositoryResults
),
ResultsWithPercentage AS
(
    SELECT
        Repository,
        Api,
        OccurrenceCount,
        CAST
        (
            100.0 * OccurrenceCount
            / NULLIF(TotalRepositoryLinqMethodOccurrences, 0)
            AS decimal(10,2)
        ) AS PercentageOfTotalRepositoryLinqMethodOccurrences,
        RepositorySortOrder
    FROM CombinedResults
)
SELECT
    Repository,
    Api,
    OccurrenceCount,
    PercentageOfTotalRepositoryLinqMethodOccurrences
FROM ResultsWithPercentage
ORDER BY
    RepositorySortOrder,
    CASE
        WHEN RepositorySortOrder = 1
            THEN PercentageOfTotalRepositoryLinqMethodOccurrences
        ELSE NULL
    END DESC,
    CASE Api
        WHEN 'Enumerable' THEN 1
        WHEN 'Queryable' THEN 2
        ELSE 3
    END,
    Repository;
GO