/*
    Get_08_02_CrossCorpus_LinqOperatorComposition.sql

    Cross-corpus comparison of LINQ operator composition.

    For each repository, reports the frequency and percentage of every
    LINQ member in the LINQ vocabulary.

    An additional ALL_REPOSITORIES row is reported for every LINQ member.

    Only semantic LINQ method calls are included:
        Occurrences.Kind = 'MethodCall'

    Query-syntax occurrences are deliberately excluded.

    Repository rows are listed first, in MethodId order.

    ALL_REPOSITORIES rows are listed last, ranked by descending
    corpus-wide percentage of LINQ method-call occurrences.
*/

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
        COUNT_BIG(*) AS TotalRepositoryLinqMethodOccurrences
    FROM dbo.Occurrences
    WHERE Kind = 'MethodCall'
    GROUP BY
        Repository,
        CommitHash
),
MemberOccurrences AS
(
    SELECT
        Repository,
        CommitHash,
        Api,
        Operator,
        COUNT_BIG(*) AS OccurrenceCount
    FROM dbo.Occurrences
    WHERE Kind = 'MethodCall'
    GROUP BY
        Repository,
        CommitHash,
        Api,
        Operator
),
RepositoryResults AS
(
    SELECT
        rc.Repository,
        m.Api,
        m.Operator,
        m.Id AS MethodId,

        COALESCE(mo.OccurrenceCount, 0)
            AS OccurrenceCount,

        COALESCE(rt.TotalRepositoryLinqMethodOccurrences, 0)
            AS TotalRepositoryLinqMethodOccurrences
    FROM RepositoryCommits AS rc

    CROSS JOIN dbo.Methods AS m

    LEFT JOIN MemberOccurrences AS mo
        ON  mo.Repository = rc.Repository
        AND mo.CommitHash = rc.CommitHash
        AND mo.Api = m.Api
        AND mo.Operator = m.Operator

    LEFT JOIN RepositoryTotals AS rt
        ON  rt.Repository = rc.Repository
        AND rt.CommitHash = rc.CommitHash
),
AllRepositoryResults AS
(
    SELECT
        'ALL_REPOSITORIES' AS Repository,
        Api,
        Operator,
        MethodId,
        SUM(OccurrenceCount) AS OccurrenceCount,
        SUM(TotalRepositoryLinqMethodOccurrences)
            AS TotalRepositoryLinqMethodOccurrences
    FROM RepositoryResults
    GROUP BY
        Api,
        Operator,
        MethodId
),
CombinedResults AS
(
    SELECT
        Repository,
        Api,
        Operator,
        MethodId,
        OccurrenceCount,
        TotalRepositoryLinqMethodOccurrences,
        0 AS RepositorySortOrder
    FROM RepositoryResults

    UNION ALL

    SELECT
        Repository,
        Api,
        Operator,
        MethodId,
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
        Operator,
        MethodId,
        OccurrenceCount,
        TotalRepositoryLinqMethodOccurrences,

        CAST
        (
            100.0
            * OccurrenceCount
            / NULLIF(TotalRepositoryLinqMethodOccurrences, 0)
            AS decimal(10,2)
        ) AS PercentageOfTotalRepositoryLinqMethodOccurrences,

        RepositorySortOrder
    FROM CombinedResults
)
SELECT
    Repository,
    Api,
    Operator,
    OccurrenceCount,
    PercentageOfTotalRepositoryLinqMethodOccurrences
FROM ResultsWithPercentage
ORDER BY
    RepositorySortOrder,

    CASE
        WHEN RepositorySortOrder = 0
            THEN MethodId
        ELSE NULL
    END,

    CASE
        WHEN RepositorySortOrder = 1
            THEN PercentageOfTotalRepositoryLinqMethodOccurrences
        ELSE NULL
    END DESC,

    CASE
        WHEN RepositorySortOrder = 1
            THEN MethodId
        ELSE NULL
    END,

    Repository;