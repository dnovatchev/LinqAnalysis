USE [LinqCorpus];
GO

/*
    Get_08_06_03_OperatorBigramContinuationSummary.sql

    Purpose:
        Report the most frequent observed continuation for each
        LINQ operator, for each repository and for ALL_REPOSITORIES.

    For each first LINQ operator:
        The selected continuation is the one with the highest
        BigramCount.

    Repository-specific rows:
        Taken from dbo.vw_OperatorBigramContinuations.

    ALL_REPOSITORIES:
        Bigram counts are combined across repositories first.
        Total continuations of each first operator are combined
        across repositories.
        The continuation ranking is then recomputed.

    This query therefore does NOT combine repository-level rank-1
    results; it identifies the rank-1 continuation in the combined
    corpus directly.

    Repository-specific rows are listed first.
    ALL_REPOSITORIES rows are listed last.

    ALL_REPOSITORIES uses the fixed sentinel CommitHash:
        FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
*/

WITH RepositoryResults AS
(
    SELECT
        v.Repository,
        v.CommitHash,
        v.RankOfThisContinuation,
        mf1.Id AS FirstMethodId,
        mf2.Id AS SecondMethodId,
        v.FirstApi,
        v.FirstOperator,
        v.SecondApi,
        v.SecondOperator,
        v.BigramCount,
        v.TotalContinuationsOfFirstMethod
    FROM dbo.vw_OperatorBigramContinuations AS v

    INNER JOIN dbo.Methods AS mf1
        ON  mf1.Api = v.FirstApi
        AND mf1.Operator = v.FirstOperator

    INNER JOIN dbo.Methods AS mf2
        ON  mf2.Api = v.SecondApi
        AND mf2.Operator = v.SecondOperator

    WHERE v.RankOfThisContinuation = 1
),
AllRepositoryBigramCounts AS
(
    SELECT
        v.FirstApi,
        v.FirstOperator,
        v.SecondApi,
        v.SecondOperator,
        mf1.Id AS FirstMethodId,
        mf2.Id AS SecondMethodId,
        SUM(v.BigramCount) AS BigramCount
    FROM dbo.vw_OperatorBigramContinuations AS v

    INNER JOIN dbo.Methods AS mf1
        ON  mf1.Api = v.FirstApi
        AND mf1.Operator = v.FirstOperator

    INNER JOIN dbo.Methods AS mf2
        ON  mf2.Api = v.SecondApi
        AND mf2.Operator = v.SecondOperator

    GROUP BY
        v.FirstApi,
        v.FirstOperator,
        v.SecondApi,
        v.SecondOperator,
        mf1.Id,
        mf2.Id
),
AllRepositoryContinuationTotals AS
(
    SELECT
        FirstMethodId,
        SUM(TotalContinuationsOfFirstMethod)
            AS TotalContinuationsOfFirstMethod
    FROM
    (
        SELECT DISTINCT
            v.Repository,
            v.CommitHash,
            mf1.Id AS FirstMethodId,
            v.TotalContinuationsOfFirstMethod
        FROM dbo.vw_OperatorBigramContinuations AS v

        INNER JOIN dbo.Methods AS mf1
            ON  mf1.Api = v.FirstApi
            AND mf1.Operator = v.FirstOperator
    ) AS RepositoryFirstMethodTotals
    GROUP BY
        FirstMethodId
),
RankedAllRepositoryContinuations AS
(
    SELECT
        'ALL_REPOSITORIES' AS Repository,
        a.FirstApi,
        a.FirstOperator,
        a.SecondApi,
        a.SecondOperator,
        a.FirstMethodId,
        a.SecondMethodId,
        a.BigramCount,
        t.TotalContinuationsOfFirstMethod,

        ROW_NUMBER() OVER
        (
            PARTITION BY
                a.FirstMethodId
            ORDER BY
                a.BigramCount DESC,
                mf2.IntroducedVersion DESC,
                mf2.Id DESC
        ) AS RankOfThisContinuation

    FROM AllRepositoryBigramCounts AS a

    INNER JOIN AllRepositoryContinuationTotals AS t
        ON t.FirstMethodId = a.FirstMethodId

    INNER JOIN dbo.Methods AS mf2
        ON mf2.Id = a.SecondMethodId
),
CombinedResults AS
(
    SELECT
        Repository,
        CommitHash,
        RankOfThisContinuation,
        FirstApi,
        FirstOperator,
        SecondApi,
        SecondOperator,
        FirstMethodId,
        SecondMethodId,
        BigramCount,
        TotalContinuationsOfFirstMethod,
        0 AS RepositorySortOrder
    FROM RepositoryResults

    UNION ALL

    SELECT
        Repository,

        -- Fixed sentinel hash for the synthetic ALL_REPOSITORIES row.
        'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF' AS CommitHash,

        RankOfThisContinuation,
        FirstApi,
        FirstOperator,
        SecondApi,
        SecondOperator,
        FirstMethodId,
        SecondMethodId,
        BigramCount,
        TotalContinuationsOfFirstMethod,
        1 AS RepositorySortOrder
    FROM RankedAllRepositoryContinuations
    WHERE RankOfThisContinuation = 1
)
SELECT
    Repository,
    CommitHash,
    RankOfThisContinuation,
    FirstApi,
    FirstOperator,
    SecondApi,
    SecondOperator,
    BigramCount,
    TotalContinuationsOfFirstMethod,

    CAST
    (
        100.0 * BigramCount
        / NULLIF(TotalContinuationsOfFirstMethod, 0)
        AS decimal(10,4)
    ) AS PercentageOfThisContinuationAmongAllContinuationsOfFirstMethod

FROM CombinedResults

ORDER BY
    RepositorySortOrder,

    CASE
        WHEN RepositorySortOrder = 0 THEN Repository
        ELSE NULL
    END,

    CASE
        WHEN RepositorySortOrder = 0 THEN CommitHash
        ELSE NULL
    END,

    FirstMethodId;
GO