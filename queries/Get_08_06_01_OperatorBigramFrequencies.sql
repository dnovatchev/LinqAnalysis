USE [LinqCorpus];
GO

/*
    Get_08_06_01_OperatorBigramFrequencies.sql

    Purpose:
        Report observed LINQ operator bigram frequencies for each
        repository and for the combined corpus.

    A bigram is one pair of adjacent LINQ members within a detected
    LINQ chain.

    For each repository:
        BigramCount = number of occurrences of the bigram.
        PercentageOfThisBigramInAllBigramsInTheCorpus =
            BigramCount / all adjacent pairs in that repository * 100.

    ALL_REPOSITORIES:
        Bigram counts are summed across repositories.
        The aggregate percentage is calculated from the combined
        number of adjacent pairs.
        The aggregate rank is calculated independently.

    Repository-specific rows are listed first.
    ALL_REPOSITORIES rows are listed last.
*/

WITH ChainMethodsOrdered AS
(
    SELECT
        cm.Repository,
        cm.CommitHash,
        cm.ChainId,
        cm.PositionInChain,
        cm.MethodId,
        LEAD(cm.MethodId) OVER
        (
            PARTITION BY
                cm.Repository,
                cm.CommitHash,
                cm.ChainId
            ORDER BY
                cm.PositionInChain
        ) AS NextMethodId
    FROM dbo.ChainMethods AS cm
),
AdjacentPairs AS
(
    SELECT
        Repository,
        CommitHash,
        ChainId,
        PositionInChain,
        MethodId AS FirstMethodId,
        NextMethodId AS SecondMethodId
    FROM ChainMethodsOrdered
    WHERE NextMethodId IS NOT NULL
),
BigramCounts AS
(
    SELECT
        Repository,
        CommitHash,
        FirstMethodId,
        SecondMethodId,
        COUNT_BIG(*) AS BigramCount
    FROM AdjacentPairs
    GROUP BY
        Repository,
        CommitHash,
        FirstMethodId,
        SecondMethodId
),
CorpusTotals AS
(
    SELECT
        Repository,
        CommitHash,
        COUNT_BIG(*) AS TotalAdjacentPairs
    FROM AdjacentPairs
    GROUP BY
        Repository,
        CommitHash
),
RankedBigrams AS
(
    SELECT
        b.Repository,
        b.CommitHash,
        b.FirstMethodId,
        b.SecondMethodId,
        b.BigramCount,
        ROW_NUMBER() OVER
        (
            PARTITION BY
                b.Repository,
                b.CommitHash
            ORDER BY
                b.BigramCount DESC,
                mf1.IntroducedVersion DESC,
                mf1.Id DESC,
                mf2.IntroducedVersion DESC,
                mf2.Id DESC
        ) AS Rank
    FROM BigramCounts AS b
    INNER JOIN dbo.Methods AS mf1
        ON mf1.Id = b.FirstMethodId
    INNER JOIN dbo.Methods AS mf2
        ON mf2.Id = b.SecondMethodId
),
AllRepositoryBigramCounts AS
(
    SELECT
        'ALL_REPOSITORIES' AS Repository,
        FirstMethodId,
        SecondMethodId,
        SUM(BigramCount) AS BigramCount
    FROM BigramCounts
    GROUP BY
        FirstMethodId,
        SecondMethodId
),
AllRepositoryTotal AS
(
    SELECT
        SUM(TotalAdjacentPairs)
            AS TotalAllRepositoryAdjacentPairs
    FROM CorpusTotals
),
RankedAllRepositoryBigrams AS
(
    SELECT
        a.Repository,
        a.FirstMethodId,
        a.SecondMethodId,
        a.BigramCount,
        ROW_NUMBER() OVER
        (
            ORDER BY
                a.BigramCount DESC,
                mf1.IntroducedVersion DESC,
                mf1.Id DESC,
                mf2.IntroducedVersion DESC,
                mf2.Id DESC
        ) AS Rank
    FROM AllRepositoryBigramCounts AS a
    INNER JOIN dbo.Methods AS mf1
        ON mf1.Id = a.FirstMethodId
    INNER JOIN dbo.Methods AS mf2
        ON mf2.Id = a.SecondMethodId
),
CombinedResults AS
(
    SELECT
        r.Repository,
        r.Rank,
        r.FirstMethodId,
        r.SecondMethodId,
        r.BigramCount,
        t.TotalAdjacentPairs,
        0 AS RepositorySortOrder
    FROM RankedBigrams AS r
    INNER JOIN CorpusTotals AS t
        ON t.Repository = r.Repository
        AND t.CommitHash = r.CommitHash

    UNION ALL

    SELECT
        r.Repository,
        r.Rank,
        r.FirstMethodId,
        r.SecondMethodId,
        r.BigramCount,
        t.TotalAllRepositoryAdjacentPairs,
        1 AS RepositorySortOrder
    FROM RankedAllRepositoryBigrams AS r
    CROSS JOIN AllRepositoryTotal AS t
)
SELECT
    r.Repository,
    r.Rank,
    mf1.Api AS FirstApi,
    mf1.Operator AS FirstOperator,
    mf2.Api AS SecondApi,
    mf2.Operator AS SecondOperator,
    r.BigramCount,

    CAST
    (
        100.0 * r.BigramCount
        / NULLIF(r.TotalAdjacentPairs, 0)
        AS decimal(10,4)
    ) AS PercentageOfThisBigramInAllBigramsInTheCorpus

FROM CombinedResults AS r

INNER JOIN dbo.Methods AS mf1
    ON mf1.Id = r.FirstMethodId

INNER JOIN dbo.Methods AS mf2
    ON mf2.Id = r.SecondMethodId

ORDER BY
    r.RepositorySortOrder,
    CASE
        WHEN r.RepositorySortOrder = 0
            THEN r.Repository
        ELSE NULL
    END,
    r.Rank;
GO