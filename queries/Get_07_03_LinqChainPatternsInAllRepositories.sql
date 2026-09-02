use LinqCorpus
go

/*
    Get_07_03_LinqChainPatterns.sql

    Frequency of complete LINQ-method chain patterns.

    Each ChainId represents one complete LINQ chain.
    The methods are reconstructed in PositionInChain order.
*/

WITH ChainsWithPatterns AS
(
    SELECT
        cm.Repository,
        cm.CommitHash,
        cm.ChainId,

        STRING_AGG(
            CAST(
                CONCAT(m.Api, '.', m.Operator)
                AS varchar(max)
            ),
            ' -> '
        ) WITHIN GROUP
        (
            ORDER BY cm.PositionInChain
        ) AS ChainPattern

    FROM dbo.ChainMethods AS cm
    INNER JOIN dbo.Methods AS m
        ON m.Id = cm.MethodId

    GROUP BY
        cm.Repository,
        cm.CommitHash,
        cm.ChainId
),
PatternCounts AS
(
    SELECT
        Repository,
        ChainPattern,
        COUNT_BIG(*) AS ChainOccurrenceCount
    FROM ChainsWithPatterns
    GROUP BY
        Repository,
        ChainPattern
),
RepositoryChainTotals AS
(
    SELECT
        Repository,
        COUNT_BIG(*) AS TotalChainCount
    FROM dbo.Chains
    GROUP BY Repository
)
SELECT
    pc.Repository,
    pc.ChainPattern,
    pc.ChainOccurrenceCount,

    CAST(
        100.0 * pc.ChainOccurrenceCount
        / NULLIF(rct.TotalChainCount, 0)
        AS decimal(6,2)
    ) AS [ChainOccurrences (% of All Chains)]

FROM PatternCounts AS pc
INNER JOIN RepositoryChainTotals AS rct
    ON rct.Repository = pc.Repository

ORDER BY
    pc.Repository,
    pc.ChainOccurrenceCount DESC,
    pc.ChainPattern;