/*
    Get_08_04_CrossCorpus_LinqChainUsageComparison.sql

    Purpose:
        Compare LINQ chain usage across repositories and summarize
        the combined results for ALL_REPOSITORIES.

    Definitions:
        - TotalLinqMethodsOccurrences = semantic LINQ MethodCall
          occurrences in the repository.
        - MethodsWithinChains = method occurrences represented by
          dbo.ChainMethods.
        - MethodsWithinChainsPercentageOfTotal =
          MethodsWithinChains / TotalLinqMethodsOccurrences * 100.
        - NumberOfChains = number of chains in dbo.Chains.
        - AverageChainLength = average ChainLength in dbo.Chains.
        - MedianChainLength = median ChainLength in dbo.Chains.
        - MaximumChainLength = maximum ChainLength in dbo.Chains.

    For ALL_REPOSITORIES:
        - Counts are summed.
        - MethodsWithinChainsPercentageOfTotal is calculated from
          the combined counts.
        - AverageChainLength is calculated from the combined number
          of chain methods and chains.
        - MedianChainLength is calculated from all chains across
          all repositories.
        - MaximumChainLength is the maximum across all repositories.

    Chain definition:
        Uses the established chain data in dbo.Chains and
        dbo.ChainMethods. Chains are not reconstructed from
        source-line adjacency.
*/

USE [LinqCorpus];
GO

WITH RepositoryTotals AS
(
    SELECT
        Repository,
        COUNT_BIG(*) AS TotalLinqMethodsOccurrences
    FROM dbo.Occurrences
    WHERE Kind = 'MethodCall'
    GROUP BY Repository
),
ChainTotals AS
(
    SELECT
        Repository,
        COUNT_BIG(*) AS NumberOfChains,
        SUM(CAST(ChainLength AS bigint)) AS TotalChainMethods,
        AVG(CAST(ChainLength AS decimal(18,4)))
            AS AverageChainLength,
        MAX(ChainLength) AS MaximumChainLength
    FROM dbo.Chains
    GROUP BY Repository
),
ChainMethodTotals AS
(
    SELECT
        Repository,
        COUNT_BIG(*) AS MethodsWithinChains
    FROM dbo.ChainMethods
    GROUP BY Repository
),
ChainMedians AS
(
    SELECT DISTINCT
        Repository,
        PERCENTILE_CONT(0.50)
            WITHIN GROUP (ORDER BY ChainLength)
            OVER (PARTITION BY Repository) AS MedianChainLength
    FROM dbo.Chains
),
RepositoryResults AS
(
    SELECT
        r.Repository,
        r.TotalLinqMethodsOccurrences,
        m.MethodsWithinChains,

        CAST
        (
            100.0 * m.MethodsWithinChains
            / NULLIF(r.TotalLinqMethodsOccurrences, 0)
            AS decimal(10,2)
        ) AS MethodsWithinChainsPercentageOfTotal,

        c.NumberOfChains,

        CAST(c.AverageChainLength AS decimal(10,2))
            AS AverageChainLength,

        CAST(med.MedianChainLength AS decimal(10,2))
            AS MedianChainLength,

        c.MaximumChainLength

    FROM RepositoryTotals AS r

    INNER JOIN ChainTotals AS c
        ON c.Repository = r.Repository

    INNER JOIN ChainMethodTotals AS m
        ON m.Repository = r.Repository

    INNER JOIN ChainMedians AS med
        ON med.Repository = r.Repository
),
AllRepositorySummary AS
(
    SELECT
        'ALL_REPOSITORIES' AS Repository,

        SUM(TotalLinqMethodsOccurrences)
            AS TotalLinqMethodsOccurrences,

        SUM(MethodsWithinChains)
            AS MethodsWithinChains,

        SUM(NumberOfChains)
            AS NumberOfChains,

        MAX(MaximumChainLength)
            AS MaximumChainLength

    FROM RepositoryResults
),
AllRepositoryMedian AS
(
    SELECT DISTINCT
        PERCENTILE_CONT(0.50)
            WITHIN GROUP (ORDER BY ChainLength)
            OVER () AS MedianChainLength
    FROM dbo.Chains
),
CombinedResults AS
(
    SELECT
        Repository,
        TotalLinqMethodsOccurrences,
        MethodsWithinChains,
        MethodsWithinChainsPercentageOfTotal,
        NumberOfChains,
        AverageChainLength,
        MedianChainLength,
        MaximumChainLength,
        0 AS RepositorySortOrder
    FROM RepositoryResults

    UNION ALL

    SELECT
        a.Repository,
        a.TotalLinqMethodsOccurrences,
        a.MethodsWithinChains,

        CAST
        (
            100.0 * a.MethodsWithinChains
            / NULLIF(a.TotalLinqMethodsOccurrences, 0)
            AS decimal(10,2)
        ) AS MethodsWithinChainsPercentageOfTotal,

        a.NumberOfChains,

        CAST
        (
            1.0 * a.MethodsWithinChains
            / NULLIF(a.NumberOfChains, 0)
            AS decimal(10,2)
        ) AS AverageChainLength,

        CAST(m.MedianChainLength AS decimal(10,2))
            AS MedianChainLength,

        a.MaximumChainLength,

        1 AS RepositorySortOrder

    FROM AllRepositorySummary AS a
    CROSS JOIN AllRepositoryMedian AS m
)
SELECT
    Repository,
    TotalLinqMethodsOccurrences,
    MethodsWithinChains,
    MethodsWithinChainsPercentageOfTotal,
    NumberOfChains,
    AverageChainLength,
    MedianChainLength,
    MaximumChainLength
FROM CombinedResults
ORDER BY
    RepositorySortOrder,
    Repository;
GO