CREATE OR ALTER VIEW dbo.vw_OperatorBigramContinuations
AS
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
        ap.Repository,
        ap.CommitHash,
        ap.FirstMethodId,
        ap.SecondMethodId,
        COUNT_BIG(*) AS BigramCount
    FROM AdjacentPairs AS ap
    GROUP BY
        ap.Repository,
        ap.CommitHash,
        ap.FirstMethodId,
        ap.SecondMethodId
),
FirstMethodTotals AS
(
    SELECT
        ap.Repository,
        ap.CommitHash,
        ap.FirstMethodId,
        COUNT_BIG(*) AS TotalContinuationsOfFirstMethod
    FROM AdjacentPairs AS ap
    GROUP BY
        ap.Repository,
        ap.CommitHash,
        ap.FirstMethodId
),
RankedContinuations AS
(
    SELECT
        b.Repository,
        b.CommitHash,
        b.FirstMethodId,
        b.SecondMethodId,
        b.BigramCount,
        t.TotalContinuationsOfFirstMethod,
        ROW_NUMBER() OVER
        (
            PARTITION BY
                b.Repository,
                b.CommitHash,
                b.FirstMethodId
            ORDER BY
                b.BigramCount DESC,
                mf2.IntroducedVersion DESC,
                mf2.Id DESC
        ) AS RankOfThisContinuation
    FROM BigramCounts AS b
    INNER JOIN FirstMethodTotals AS t
        ON t.Repository = b.Repository
        AND t.CommitHash = b.CommitHash
        AND t.FirstMethodId = b.FirstMethodId
    INNER JOIN dbo.Methods AS mf2
        ON mf2.Id = b.SecondMethodId
)
SELECT
    r.Repository,
    r.CommitHash,
    r.RankOfThisContinuation,
    mf1.Api AS FirstApi,
    mf1.Operator AS FirstOperator,
    mf2.Api AS SecondApi,
    mf2.Operator AS SecondOperator,
    r.BigramCount,
    r.TotalContinuationsOfFirstMethod,
    CAST
    (
        100.0 * r.BigramCount
        / NULLIF(r.TotalContinuationsOfFirstMethod, 0)
        AS decimal(10,4)
    ) AS PercentageOfThisContinuationAmongAllContinuationsOfFirstMethod
FROM RankedContinuations AS r
INNER JOIN dbo.Methods AS mf1
    ON mf1.Id = r.FirstMethodId
INNER JOIN dbo.Methods AS mf2
    ON mf2.Id = r.SecondMethodId;
GO