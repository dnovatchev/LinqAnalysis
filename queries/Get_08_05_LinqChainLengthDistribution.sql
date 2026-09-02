/*
    Get_08_05_LinqChainLengthDistribution.sql

    Purpose:
        Show the distribution of observed LINQ method-chains by length.

    For each repository and each observed chain length, report:

        - DifferentChainPatterns:
          The number of distinct LINQ chain patterns having this length.

        - AllChainsWithThisLength:
          The total number of observed chain occurrences having this length.

    A chain pattern is the sequence of LINQ API-methods forming a chain,
    reconstructed from dbo.ChainMethods in PositionInChain order.

    Thus, if several different chain patterns have the same length,
    DifferentChainPatterns counts those distinct patterns, while
    AllChainsWithThisLength counts all occurrences of those patterns.

    For ALL_REPOSITORIES:
        - DifferentChainPatterns is the number of distinct chain patterns
          across all repositories.
        - AllChainsWithThisLength is the total number of chain occurrences
          across all repositories having the specified length.
*/

USE [LinqCorpus];
GO

WITH ChainsWithPatterns AS
(
    SELECT
        cm.Repository,
        cm.CommitHash,
        cm.ChainId,
        c.ChainLength,

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

    INNER JOIN dbo.Chains AS c
        ON  c.Repository = cm.Repository
        AND c.CommitHash = cm.CommitHash
        AND c.ChainId = cm.ChainId

    INNER JOIN dbo.Methods AS m
        ON m.Id = cm.MethodId

    GROUP BY
        cm.Repository,
        cm.CommitHash,
        cm.ChainId,
        c.ChainLength
),
PatternCounts AS
(
    SELECT
        Repository,
        ChainLength,
        ChainPattern,
        COUNT_BIG(*) AS ChainOccurrenceCount

    FROM ChainsWithPatterns

    GROUP BY
        Repository,
        ChainLength,
        ChainPattern
),
LengthDistribution AS
(
    SELECT
        Repository,
        ChainLength,

        COUNT_BIG(*) AS DifferentChainPatterns,

        SUM(ChainOccurrenceCount)
            AS AllChainsWithThisLength

    FROM PatternCounts

    GROUP BY
        Repository,
        ChainLength
),
AllRepositoryDistribution AS
(
    SELECT
        'ALL_REPOSITORIES' AS Repository,
        ChainLength,

        COUNT_BIG(*) AS DifferentChainPatterns,

        SUM(ChainOccurrenceCount)
            AS AllChainsWithThisLength

    FROM
    (
        SELECT
            ChainLength,
            ChainPattern,
            SUM(ChainOccurrenceCount) AS ChainOccurrenceCount

        FROM PatternCounts

        GROUP BY
            ChainLength,
            ChainPattern
    ) AS CombinedPatterns

    GROUP BY
        ChainLength
),
CombinedResults AS
(
    SELECT
        Repository,
        ChainLength,
        DifferentChainPatterns,
        AllChainsWithThisLength,
        0 AS RepositorySortOrder

    FROM LengthDistribution

    UNION ALL

    SELECT
        Repository,
        ChainLength,
        DifferentChainPatterns,
        AllChainsWithThisLength,
        1 AS RepositorySortOrder

    FROM AllRepositoryDistribution
)
SELECT
    Repository,
    ChainLength,
    DifferentChainPatterns,
    AllChainsWithThisLength

FROM CombinedResults

ORDER BY
    RepositorySortOrder,
    Repository,
    ChainLength;
GO