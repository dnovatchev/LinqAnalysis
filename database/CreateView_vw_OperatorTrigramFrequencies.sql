USE [LinqCorpus];
GO

CREATE OR ALTER VIEW dbo.vw_OperatorTrigramFrequencies
AS
WITH ChainMethodsOrdered AS
(
    SELECT
        cm.Repository,
        cm.CommitHash,
        cm.ChainId,
        cm.PositionInChain,
        cm.MethodId,
        LEAD(cm.MethodId, 1) OVER
        (
            PARTITION BY
                cm.Repository,
                cm.CommitHash,
                cm.ChainId
            ORDER BY
                cm.PositionInChain
        ) AS SecondMethodId,
        LEAD(cm.MethodId, 2) OVER
        (
            PARTITION BY
                cm.Repository,
                cm.CommitHash,
                cm.ChainId
            ORDER BY
                cm.PositionInChain
        ) AS ThirdMethodId
    FROM dbo.ChainMethods AS cm
),
Trigrams AS
(
    SELECT
        Repository,
        CommitHash,
        ChainId,
        PositionInChain,
        MethodId AS FirstMethodId,
        SecondMethodId,
        ThirdMethodId
    FROM ChainMethodsOrdered
    WHERE
        SecondMethodId IS NOT NULL
        AND ThirdMethodId IS NOT NULL
),

/* ------------------------------------------------------------
   Repository-specific trigram counts
   ------------------------------------------------------------ */

RepositoryTrigramCounts AS
(
    SELECT
        Repository,
        CommitHash,
        FirstMethodId,
        SecondMethodId,
        ThirdMethodId,
        COUNT_BIG(*) AS TrigramCount
    FROM Trigrams
    GROUP BY
        Repository,
        CommitHash,
        FirstMethodId,
        SecondMethodId,
        ThirdMethodId
),

RepositoryTotals AS
(
    SELECT
        Repository,
        CommitHash,
        COUNT_BIG(*) AS TotalTrigrams
    FROM Trigrams
    GROUP BY
        Repository,
        CommitHash
),

RankedRepositoryTrigrams AS
(
    SELECT
        t.Repository,
        t.CommitHash,
        t.FirstMethodId,
        t.SecondMethodId,
        t.ThirdMethodId,
        t.TrigramCount,
        ROW_NUMBER() OVER
        (
            PARTITION BY
                t.Repository,
                t.CommitHash
            ORDER BY
                t.TrigramCount DESC,
                mf1.IntroducedVersion DESC,
                mf1.Id DESC,
                mf2.IntroducedVersion DESC,
                mf2.Id DESC,
                mf3.IntroducedVersion DESC,
                mf3.Id DESC
        ) AS Rank
    FROM RepositoryTrigramCounts AS t
    INNER JOIN dbo.Methods AS mf1
        ON mf1.Id = t.FirstMethodId
    INNER JOIN dbo.Methods AS mf2
        ON mf2.Id = t.SecondMethodId
    INNER JOIN dbo.Methods AS mf3
        ON mf3.Id = t.ThirdMethodId
),

/* ------------------------------------------------------------
   Corpus-wide trigram counts
   ------------------------------------------------------------ */

AllRepositoryTrigramCounts AS
(
    SELECT
        FirstMethodId,
        SecondMethodId,
        ThirdMethodId,
        SUM(TrigramCount) AS TrigramCount
    FROM RepositoryTrigramCounts
    GROUP BY
        FirstMethodId,
        SecondMethodId,
        ThirdMethodId
),

AllRepositoryTotal AS
(
    SELECT
        SUM(TotalTrigrams) AS TotalTrigrams
    FROM RepositoryTotals
),

RankedAllRepositoryTrigrams AS
(
    SELECT
        t.FirstMethodId,
        t.SecondMethodId,
        t.ThirdMethodId,
        t.TrigramCount,
        ROW_NUMBER() OVER
        (
            ORDER BY
                t.TrigramCount DESC,
                mf1.IntroducedVersion DESC,
                mf1.Id DESC,
                mf2.IntroducedVersion DESC,
                mf2.Id DESC,
                mf3.IntroducedVersion DESC,
                mf3.Id DESC
        ) AS Rank
    FROM AllRepositoryTrigramCounts AS t
    INNER JOIN dbo.Methods AS mf1
        ON mf1.Id = t.FirstMethodId
    INNER JOIN dbo.Methods AS mf2
        ON mf2.Id = t.SecondMethodId
    INNER JOIN dbo.Methods AS mf3
        ON mf3.Id = t.ThirdMethodId
)

/* ------------------------------------------------------------
   Repository-specific rows
   ------------------------------------------------------------ */

SELECT
    r.Repository,
    r.CommitHash,
    r.Rank,
    mf1.Api AS FirstApi,
    mf1.Operator AS FirstOperator,
    mf2.Api AS SecondApi,
    mf2.Operator AS SecondOperator,
    mf3.Api AS ThirdApi,
    mf3.Operator AS ThirdOperator,
    r.TrigramCount,
    CAST
    (
        100.0 * r.TrigramCount
        / NULLIF(rt.TotalTrigrams, 0)
        AS decimal(10,4)
    ) AS PercentageOfThisTrigramInAllTrigramsInTheCorpus
FROM RankedRepositoryTrigrams AS r
INNER JOIN dbo.Methods AS mf1
    ON mf1.Id = r.FirstMethodId
INNER JOIN dbo.Methods AS mf2
    ON mf2.Id = r.SecondMethodId
INNER JOIN dbo.Methods AS mf3
    ON mf3.Id = r.ThirdMethodId
INNER JOIN RepositoryTotals AS rt
    ON rt.Repository = r.Repository
    AND rt.CommitHash = r.CommitHash

UNION ALL

/* ------------------------------------------------------------
   ALL_REPOSITORIES rows
   ------------------------------------------------------------ */

SELECT
    'ALL_REPOSITORIES' AS Repository,
    CAST(NULL AS char(40)) AS CommitHash,
    r.Rank,
    mf1.Api AS FirstApi,
    mf1.Operator AS FirstOperator,
    mf2.Api AS SecondApi,
    mf2.Operator AS SecondOperator,
    mf3.Api AS ThirdApi,
    mf3.Operator AS ThirdOperator,
    r.TrigramCount,
    CAST
    (
        100.0 * r.TrigramCount
        / NULLIF(at.TotalTrigrams, 0)
        AS decimal(10,4)
    ) AS PercentageOfThisTrigramInAllTrigramsInTheCorpus
FROM RankedAllRepositoryTrigrams AS r
INNER JOIN dbo.Methods AS mf1
    ON mf1.Id = r.FirstMethodId
INNER JOIN dbo.Methods AS mf2
    ON mf2.Id = r.SecondMethodId
INNER JOIN dbo.Methods AS mf3
    ON mf3.Id = r.ThirdMethodId
CROSS JOIN AllRepositoryTotal AS at;
GO