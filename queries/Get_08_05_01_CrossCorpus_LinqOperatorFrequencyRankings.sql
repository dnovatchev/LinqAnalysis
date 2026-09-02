/*
    Get_08_05_CrossCorpus_LinqOperatorFrequencyRankings.sql

    Purpose:
        Produce the LINQ operator frequency distribution for each
        repository, ranked from most frequently used to least
        frequently used, followed by an aggregate ranking for
        ALL_REPOSITORIES.

    Ranking:
        1. OccurrenceCount descending.
        2. Methods.Id descending for ties, so newer methods rank first.
        3. Api and Operator provide a final deterministic tie-breaker.

    Notes:
        - All methods in dbo.Methods are included, including methods
          with zero occurrences.
        - Rank is assigned independently within each repository.
        - ALL_REPOSITORIES is ranked independently from the combined
          occurrence counts.
        - ROW_NUMBER() gives exactly one rank for each method.
        - Only semantic LINQ method calls are included.
        - QuerySyntax occurrences are excluded.
*/

USE [LinqCorpus];
GO

WITH RepositoryCommits AS
(
    SELECT
        Repository,
        CommitHash
    FROM dbo.CorpusMeasurement
),
RepositoryTotals AS
(
    SELECT
        Repository,
        CommitHash,
        COUNT_BIG(*) AS TotalLinqMethodOccurrences
    FROM dbo.Occurrences
    WHERE Kind = 'MethodCall'
    GROUP BY
        Repository,
        CommitHash
),
MethodCounts AS
(
    SELECT
        rc.Repository,
        rc.CommitHash,
        m.Id AS MethodId,
        m.Api,
        m.Operator,
        COUNT_BIG(o.OccurrenceId) AS OccurrenceCount
    FROM RepositoryCommits AS rc
    CROSS JOIN dbo.Methods AS m
    LEFT JOIN dbo.Occurrences AS o
        ON  o.Repository = rc.Repository
        AND o.CommitHash = rc.CommitHash
        AND o.Api = m.Api
        AND o.Operator = m.Operator
        AND o.Kind = 'MethodCall'
    GROUP BY
        rc.Repository,
        rc.CommitHash,
        m.Id,
        m.Api,
        m.Operator
),
RankedMethods AS
(
    SELECT
        Repository,
        CommitHash,
        MethodId,
        Api,
        Operator,
        OccurrenceCount,

        ROW_NUMBER() OVER
        (
            PARTITION BY
                Repository,
                CommitHash
            ORDER BY
                OccurrenceCount DESC,
                MethodId DESC,
                Api,
                Operator
        ) AS Rank
    FROM MethodCounts
),
AllRepositoryMethodCounts AS
(
    SELECT
        'ALL_REPOSITORIES' AS Repository,
        m.MethodId,
        m.Api,
        m.Operator,
        SUM(m.OccurrenceCount) AS OccurrenceCount
    FROM
    (
        SELECT
            Repository,
            MethodId,
            Api,
            Operator,
            OccurrenceCount
        FROM MethodCounts
    ) AS m
    GROUP BY
        m.MethodId,
        m.Api,
        m.Operator
),
AllRepositoryTotal AS
(
    SELECT
        SUM(TotalLinqMethodOccurrences)
            AS TotalAllRepositoryLinqMethodOccurrences
    FROM RepositoryTotals
),
RankedAllRepositories AS
(
    SELECT
        a.Repository,
        a.MethodId,
        a.Api,
        a.Operator,
        a.OccurrenceCount,

        ROW_NUMBER() OVER
        (
            ORDER BY
                a.OccurrenceCount DESC,
                a.MethodId DESC,
                a.Api,
                a.Operator
        ) AS Rank,

        art.TotalAllRepositoryLinqMethodOccurrences
    FROM AllRepositoryMethodCounts AS a
    CROSS JOIN AllRepositoryTotal AS art
),
CombinedResults AS
(
    SELECT
        r.Repository,
        r.Rank,
        r.Api,
        r.Operator,
        r.MethodId,
        r.OccurrenceCount,
        rt.TotalLinqMethodOccurrences,
        0 AS RepositorySortOrder
    FROM RankedMethods AS r
    INNER JOIN RepositoryTotals AS rt
        ON  rt.Repository = r.Repository
        AND rt.CommitHash = r.CommitHash

    UNION ALL

    SELECT
        r.Repository,
        r.Rank,
        r.Api,
        r.Operator,
        r.MethodId,
        r.OccurrenceCount,
        r.TotalAllRepositoryLinqMethodOccurrences,
        1 AS RepositorySortOrder
    FROM RankedAllRepositories AS r
)
SELECT
    Repository,
    Rank,
    Api,
    Operator,
    OccurrenceCount,

    CAST
    (
        100.0 * OccurrenceCount
        / NULLIF(TotalLinqMethodOccurrences, 0)
        AS decimal(10,2)
    ) AS PercentageOfTotalLinqMethodOccurrences

FROM CombinedResults

ORDER BY
    RepositorySortOrder,
    CASE
        WHEN RepositorySortOrder = 0
            THEN Repository
        ELSE NULL
    END,
    Rank;
GO