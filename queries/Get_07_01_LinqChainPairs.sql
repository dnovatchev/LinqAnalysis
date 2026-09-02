/*
    Get_07_LinqChainPatterns.sql

    Result set 1:
        Frequency of consecutive LINQ-method pairs within chains.

    A pair consists of two consecutive methods in the same chain.

    Example:
        Where -> Select -> ToList

    produces:
        Where -> Select
        Select -> ToList
*/

WITH MethodPairs AS
(
    SELECT
        cm1.Repository,
        cm1.CommitHash,
        cm1.ChainId,
        cm1.PositionInChain AS PreviousPosition,
        cm1.MethodId AS PreviousMethodId,
        cm2.MethodId AS NextMethodId
    FROM dbo.ChainMethods AS cm1
    INNER JOIN dbo.ChainMethods AS cm2
        ON  cm2.Repository = cm1.Repository
        AND cm2.CommitHash = cm1.CommitHash
        AND cm2.ChainId = cm1.ChainId
        AND cm2.PositionInChain = cm1.PositionInChain + 1
),
PairCounts AS
(
    SELECT
        Repository,
        PreviousMethodId,
        NextMethodId,
        COUNT_BIG(*) AS PairOccurrenceCount
    FROM MethodPairs
    GROUP BY
        Repository,
        PreviousMethodId,
        NextMethodId
),
RepositoryPairTotals AS
(
    SELECT
        Repository,
        COUNT_BIG(*) AS TotalPairCount
    FROM MethodPairs
    GROUP BY Repository
)
SELECT
    pc.Repository,
    previousMethod.Api AS PreviousApi,
    previousMethod.Operator AS PreviousMethod,
    nextMethod.Api AS NextApi,
    nextMethod.Operator AS NextMethod,
    pc.PairOccurrenceCount,

    CAST(
        100.0 * pc.PairOccurrenceCount
        / NULLIF(rpt.TotalPairCount, 0)
        AS decimal(6,2)
    ) AS ThisPairCountVsTotalPairCount

FROM PairCounts AS pc
INNER JOIN RepositoryPairTotals AS rpt
    ON rpt.Repository = pc.Repository
INNER JOIN dbo.Methods AS previousMethod
    ON previousMethod.Id = pc.PreviousMethodId
INNER JOIN dbo.Methods AS nextMethod
    ON nextMethod.Id = pc.NextMethodId

ORDER BY
    pc.Repository,
    pc.PairOccurrenceCount DESC,
    previousMethod.Api,
    previousMethod.Operator,
    nextMethod.Api,
    nextMethod.Operator;