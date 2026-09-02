USE [LinqCorpus];
GO

CREATE OR ALTER VIEW dbo.vw_OperatorTrigramContinuations
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
        ) AS ThirdMethodId,

        LEAD(cm.MethodId, 3) OVER
        (
            PARTITION BY
                cm.Repository,
                cm.CommitHash,
                cm.ChainId
            ORDER BY
                cm.PositionInChain
        ) AS FourthMethodId
    FROM dbo.ChainMethods AS cm
),
Continuations AS
(
    SELECT
        Repository,
        CommitHash,
        FirstMethodId,
        SecondMethodId,
        ThirdMethodId,
        FourthMethodId
    FROM
    (
        SELECT
            Repository,
            CommitHash,
            MethodId AS FirstMethodId,
            SecondMethodId,
            ThirdMethodId,
            FourthMethodId
        FROM ChainMethodsOrdered
    ) AS x
    WHERE
        SecondMethodId IS NOT NULL
        AND ThirdMethodId IS NOT NULL
        AND FourthMethodId IS NOT NULL
),
/*
    Repository-specific continuation counts.
*/
RepositoryContinuationCounts AS
(
    SELECT
        Repository,
        CommitHash,
        FirstMethodId,
        SecondMethodId,
        ThirdMethodId,
        FourthMethodId,
        COUNT_BIG(*) AS TrigramContinuationCount
    FROM Continuations
    GROUP BY
        Repository,
        CommitHash,
        FirstMethodId,
        SecondMethodId,
        ThirdMethodId,
        FourthMethodId
),
/*
    Total continuations for each trigram in each repository.
*/
RepositoryTrigramTotals AS
(
    SELECT
        Repository,
        CommitHash,
        FirstMethodId,
        SecondMethodId,
        ThirdMethodId,
        COUNT_BIG(*) AS TotalContinuationsFromThisTrigram
    FROM Continuations
    GROUP BY
        Repository,
        CommitHash,
        FirstMethodId,
        SecondMethodId,
        ThirdMethodId
),
/*
    Rank repository-specific continuations.
*/
RepositoryRanked AS
(
    SELECT
        c.Repository,
        c.CommitHash,
        c.FirstMethodId,
        c.SecondMethodId,
        c.ThirdMethodId,
        c.FourthMethodId,
        c.TrigramContinuationCount,
        ROW_NUMBER() OVER
        (
            PARTITION BY
                c.Repository,
                c.CommitHash,
                c.FirstMethodId,
                c.SecondMethodId,
                c.ThirdMethodId
            ORDER BY
                c.TrigramContinuationCount DESC,
                mf4.IntroducedVersion DESC,
                mf4.Id DESC
        ) AS RankOfThisContinuation
    FROM RepositoryContinuationCounts AS c
    INNER JOIN dbo.Methods AS mf4
        ON mf4.Id = c.FourthMethodId
),
/*
    Pooled continuation counts across all repositories.
*/
AllRepositoryContinuationCounts AS
(
    SELECT
        FirstMethodId,
        SecondMethodId,
        ThirdMethodId,
        FourthMethodId,
        COUNT_BIG(*) AS TrigramContinuationCount
    FROM Continuations
    GROUP BY
        FirstMethodId,
        SecondMethodId,
        ThirdMethodId,
        FourthMethodId
),
/*
    Total pooled continuations for each trigram.
*/
AllRepositoryTrigramTotals AS
(
    SELECT
        FirstMethodId,
        SecondMethodId,
        ThirdMethodId,
        COUNT_BIG(*) AS TotalContinuationsFromThisTrigram
    FROM Continuations
    GROUP BY
        FirstMethodId,
        SecondMethodId,
        ThirdMethodId
),
/*
    Rank pooled continuations.
*/
AllRepositoryRanked AS
(
    SELECT
        c.FirstMethodId,
        c.SecondMethodId,
        c.ThirdMethodId,
        c.FourthMethodId,
        c.TrigramContinuationCount,
        ROW_NUMBER() OVER
        (
            PARTITION BY
                c.FirstMethodId,
                c.SecondMethodId,
                c.ThirdMethodId
            ORDER BY
                c.TrigramContinuationCount DESC,
                mf4.IntroducedVersion DESC,
                mf4.Id DESC
        ) AS RankOfThisContinuation
    FROM AllRepositoryContinuationCounts AS c
    INNER JOIN dbo.Methods AS mf4
        ON mf4.Id = c.FourthMethodId
)

SELECT
    r.Repository,
    r.CommitHash,
    r.RankOfThisContinuation,

    mf1.Api AS FirstApi,
    mf1.Operator AS FirstOperator,

    mf2.Api AS SecondApi,
    mf2.Operator AS SecondOperator,

    mf3.Api AS ThirdApi,
    mf3.Operator AS ThirdOperator,

    mf4.Api AS FourthApi,
    mf4.Operator AS FourthOperator,

    r.TrigramContinuationCount,
    rt.TotalContinuationsFromThisTrigram,

    CAST
    (
        100.0 * r.TrigramContinuationCount
        / NULLIF(rt.TotalContinuationsFromThisTrigram, 0)
        AS decimal(10,4)
    ) AS PercentageOfThisContinuationAmongAllContinuationsOfThisTrigram
FROM RepositoryRanked AS r
INNER JOIN dbo.Methods AS mf1
    ON mf1.Id = r.FirstMethodId
INNER JOIN dbo.Methods AS mf2
    ON mf2.Id = r.SecondMethodId
INNER JOIN dbo.Methods AS mf3
    ON mf3.Id = r.ThirdMethodId
INNER JOIN dbo.Methods AS mf4
    ON mf4.Id = r.FourthMethodId
INNER JOIN RepositoryTrigramTotals AS rt
    ON rt.Repository = r.Repository
    AND rt.CommitHash = r.CommitHash
    AND rt.FirstMethodId = r.FirstMethodId
    AND rt.SecondMethodId = r.SecondMethodId
    AND rt.ThirdMethodId = r.ThirdMethodId

UNION ALL

SELECT
    'ALL_REPOSITORIES' AS Repository,
    'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF' AS CommitHash,
    r.RankOfThisContinuation,

    mf1.Api AS FirstApi,
    mf1.Operator AS FirstOperator,

    mf2.Api AS SecondApi,
    mf2.Operator AS SecondOperator,

    mf3.Api AS ThirdApi,
    mf3.Operator AS ThirdOperator,

    mf4.Api AS FourthApi,
    mf4.Operator AS FourthOperator,

    r.TrigramContinuationCount,
    rt.TotalContinuationsFromThisTrigram,

    CAST
    (
        100.0 * r.TrigramContinuationCount
        / NULLIF(rt.TotalContinuationsFromThisTrigram, 0)
        AS decimal(10,4)
    ) AS PercentageOfThisContinuationAmongAllContinuationsOfThisTrigram
FROM AllRepositoryRanked AS r
INNER JOIN dbo.Methods AS mf1
    ON mf1.Id = r.FirstMethodId
INNER JOIN dbo.Methods AS mf2
    ON mf2.Id = r.SecondMethodId
INNER JOIN dbo.Methods AS mf3
    ON mf3.Id = r.ThirdMethodId
INNER JOIN dbo.Methods AS mf4
    ON mf4.Id = r.FourthMethodId
INNER JOIN AllRepositoryTrigramTotals AS rt
    ON rt.FirstMethodId = r.FirstMethodId
    AND rt.SecondMethodId = r.SecondMethodId
    AND rt.ThirdMethodId = r.ThirdMethodId;
GO