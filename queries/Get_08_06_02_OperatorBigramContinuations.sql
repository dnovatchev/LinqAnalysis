/*
    Get_08_06_02_OperatorBigramContinuations.sql

    Purpose:
        Report the observed continuations of each LINQ operator,
        for each repository and for ALL_REPOSITORIES.

    For a first LINQ operator A:

        TotalContinuationsOfFirstMethod
            = total number of observed adjacent pairs beginning with A.

        PercentageOfThisContinuationAmongAllContinuationsOfFirstMethod
            = BigramCount / TotalContinuationsOfFirstMethod * 100.

    ALL_REPOSITORIES:
        Bigram counts are summed across repositories.
        Continuation totals are summed across repositories.
        Continuation percentages are then calculated from those
        combined counts.

    Ranking is recomputed independently for ALL_REPOSITORIES.

    Repository-specific rows are listed first.
    ALL_REPOSITORIES rows are listed last.
*/

USE [LinqCorpus];
GO

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
),
AllRepositoryBigramCounts AS
(
    SELECT
        'ALL_REPOSITORIES' AS Repository,
        FirstMethodId,
        SecondMethodId,
        FirstApi,
        FirstOperator,
        SecondApi,
        SecondOperator,
        SUM(BigramCount) AS BigramCount
    FROM RepositoryResults
    GROUP BY
        FirstMethodId,
        SecondMethodId,
        FirstApi,
        FirstOperator,
        SecondApi,
        SecondOperator
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
            Repository,
            CommitHash,
            FirstMethodId,
            TotalContinuationsOfFirstMethod
        FROM RepositoryResults
    ) AS x
    GROUP BY
        FirstMethodId
),
RankedAllRepositoryContinuations AS
(
    SELECT
        a.Repository,
        a.FirstMethodId,
        a.SecondMethodId,
        a.FirstApi,
        a.FirstOperator,
        a.SecondApi,
        a.SecondOperator,
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
        FirstMethodId,
        SecondMethodId,
        FirstApi,
        FirstOperator,
        SecondApi,
        SecondOperator,
        BigramCount,
        TotalContinuationsOfFirstMethod,
        0 AS RepositorySortOrder
    FROM RepositoryResults

    UNION ALL

    SELECT
        Repository,
        NULL AS CommitHash,
        RankOfThisContinuation,
        FirstMethodId,
        SecondMethodId,
        FirstApi,
        FirstOperator,
        SecondApi,
        SecondOperator,
        BigramCount,
        TotalContinuationsOfFirstMethod,
        1 AS RepositorySortOrder
    FROM RankedAllRepositoryContinuations
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

    CASE
        WHEN RepositorySortOrder = 0 THEN FirstMethodId
        ELSE FirstMethodId
    END,

    RankOfThisContinuation;
GO