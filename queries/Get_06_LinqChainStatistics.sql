/*
    Get_06_LinqChainStatistics.sql

    Purpose:
        Summarize LINQ chain characteristics per repository.

    Definitions:
        - A LINQ chain contains at least 2 LINQ methods.
        - TotalRepositoryLinqMethods = semantic LINQ MethodCall
          occurrences in the repository.
        - MethodsWithinChains = method positions represented by
          ChainMethods.
        - MethodsWithinChainsVsTotalRepositoryLinqMethods =
          MethodsWithinChains / TotalRepositoryLinqMethods * 100.
*/

WITH RepositoryMethods AS
(
    SELECT
        Repository,
        COUNT_BIG(*) AS TotalRepositoryLinqMethods
    FROM dbo.Occurrences
    WHERE Kind = 'MethodCall'
    GROUP BY Repository
),
ChainAggregates AS
(
    SELECT
        Repository,
        COUNT_BIG(*) AS NumberOfChains,
        SUM(CAST(ChainLength AS bigint)) AS TotalMethodsInChains,
        AVG(CAST(ChainLength AS decimal(18,4))) AS AverageChainLength,
        MIN(ChainLength) AS MinimumChainLength,
        MAX(ChainLength) AS MaximumChainLength
    FROM dbo.Chains
    GROUP BY Repository
),
ChainPercentiles AS
(
    SELECT DISTINCT
        Repository,

        PERCENTILE_CONT(0.50)
            WITHIN GROUP (ORDER BY ChainLength)
            OVER (PARTITION BY Repository) AS MedianChainLength,

        PERCENTILE_CONT(0.25)
            WITHIN GROUP (ORDER BY ChainLength)
            OVER (PARTITION BY Repository) AS ChainLengthP25,

        PERCENTILE_CONT(0.75)
            WITHIN GROUP (ORDER BY ChainLength)
            OVER (PARTITION BY Repository) AS ChainLengthP75,

        PERCENTILE_CONT(0.90)
            WITHIN GROUP (ORDER BY ChainLength)
            OVER (PARTITION BY Repository) AS ChainLengthP90,

        PERCENTILE_CONT(0.95)
            WITHIN GROUP (ORDER BY ChainLength)
            OVER (PARTITION BY Repository) AS ChainLengthP95

    FROM dbo.Chains
),
ChainMethodCounts AS
(
    SELECT
        Repository,
        COUNT_BIG(*) AS MethodsWithinChains
    FROM dbo.ChainMethods
    GROUP BY Repository
)
SELECT
    a.Repository,
    a.NumberOfChains,
    r.TotalRepositoryLinqMethods,
    m.MethodsWithinChains,

    CAST(
        100.0 * m.MethodsWithinChains
        / NULLIF(r.TotalRepositoryLinqMethods, 0)
        AS decimal(6,2)
    ) AS MethodsWithinChainsVsTotalRepositoryLinqMethods,

    CAST(a.AverageChainLength AS decimal(10,2))
        AS AverageChainLength,

    CAST(p.MedianChainLength AS decimal(10,2))
        AS MedianChainLength,

    a.MinimumChainLength,
    a.MaximumChainLength,

    CAST(p.ChainLengthP25 AS decimal(10,2))
        AS ChainLengthP25,

    CAST(p.ChainLengthP75 AS decimal(10,2))
        AS ChainLengthP75,

    CAST(p.ChainLengthP90 AS decimal(10,2))
        AS ChainLengthP90,

    CAST(p.ChainLengthP95 AS decimal(10,2))
        AS ChainLengthP95

FROM ChainAggregates a
INNER JOIN RepositoryMethods r
    ON r.Repository = a.Repository
INNER JOIN ChainMethodCounts m
    ON m.Repository = a.Repository
INNER JOIN ChainPercentiles p
    ON p.Repository = a.Repository
ORDER BY
    a.Repository;