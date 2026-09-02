/*
    Get_08_05_02_RankFrequencyAnalysis.sql

    Purpose:
        Prepare LINQ operator frequency data for rank-frequency
        distribution analysis for each repository and for the
        combined corpus.

    Definitions:
        - Rank is assigned independently within each repository and
          independently for ALL_REPOSITORIES.
        - Operators are ranked by descending occurrence count.
        - Ties are resolved by Methods.Id descending, so that the
          newer LINQ method is ranked first.
        - Operators with zero occurrences are excluded.
        - LogRank and LogOccurrenceCount are base-10 logarithms.

    The ALL_REPOSITORIES counts are obtained by summing the occurrence
    counts of each API-qualified LINQ member across all repositories.
    Its ranks and logarithms are then calculated independently from
    those aggregate counts.
*/

USE [LinqCorpus];
GO

WITH OperatorFrequencies AS
(
    SELECT
        o.Repository,
        o.Api,
        o.Operator,
        COUNT_BIG(*) AS OccurrenceCount,
        MAX(m.Id) AS MethodId
    FROM dbo.Occurrences AS o
    INNER JOIN dbo.Methods AS m
        ON  m.Api = o.Api
        AND m.Operator = o.Operator
    WHERE o.Kind = 'MethodCall'
    GROUP BY
        o.Repository,
        o.Api,
        o.Operator
),
RankedOperators AS
(
    SELECT
        Repository,
        Api,
        Operator,
        OccurrenceCount,
        ROW_NUMBER() OVER
        (
            PARTITION BY Repository
            ORDER BY
                OccurrenceCount DESC,
                MethodId DESC
        ) AS Rank
    FROM OperatorFrequencies
),
AllRepositoryFrequencies AS
(
    SELECT
        'ALL_REPOSITORIES' AS Repository,
        Api,
        Operator,
        SUM(OccurrenceCount) AS OccurrenceCount,
        MAX(MethodId) AS MethodId
    FROM OperatorFrequencies
    GROUP BY
        Api,
        Operator
),
RankedAllRepositories AS
(
    SELECT
        Repository,
        Api,
        Operator,
        OccurrenceCount,
        ROW_NUMBER() OVER
        (
            ORDER BY
                OccurrenceCount DESC,
                MethodId DESC
        ) AS Rank
    FROM AllRepositoryFrequencies
),
CombinedResults AS
(
    SELECT
        Repository,
        Rank,
        Api,
        Operator,
        OccurrenceCount,
        0 AS RepositorySortOrder
    FROM RankedOperators

    UNION ALL

    SELECT
        Repository,
        Rank,
        Api,
        Operator,
        OccurrenceCount,
        1 AS RepositorySortOrder
    FROM RankedAllRepositories
)
SELECT
    Repository,
    Rank,
    Api,
    Operator,
    OccurrenceCount,

    CAST(
        LOG10(CAST(Rank AS float))
        AS decimal(12,6)
    ) AS LogRank,

    CAST(
        LOG10(CAST(OccurrenceCount AS float))
        AS decimal(12,6)
    ) AS LogOccurrenceCount

FROM CombinedResults
ORDER BY
    RepositorySortOrder,
    CASE
        WHEN RepositorySortOrder = 0 THEN Repository
        ELSE NULL
    END,
    Rank;
GO