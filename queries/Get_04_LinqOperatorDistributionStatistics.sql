/*
    Get_04_LinqOperatorDistributionStatistics.sql

    Per-repository statistics describing the distribution of
    semantic LINQ method-call usage.

    All result measures are COUNTS of distinct (Api, Operator)
    combinations.

    UsedOperators:
        Number of (Api, Operator) combinations with at least one
        semantic MethodCall occurrence.

    OperatorsIn50Pct / 80Pct / 90Pct / 95Pct:
        Minimum number of highest-frequency USED operators whose
        cumulative occurrence count reaches at least the specified
        percentage of the repository's total semantic MethodCall
        occurrences.

    OperatorsLessThan3Pct / 2Pct / 1Pct:
        Number of USED operators whose individual percentage of the
        repository's total semantic MethodCall occurrences is
        strictly less than the specified percentage.

    CompletelyUnusedOperators:
        Number of (Api, Operator) combinations with zero semantic
        MethodCall occurrences.

    QuerySyntax occurrences are excluded.
    Repository names are not hardcoded.
*/

WITH OperatorFrequencies AS
(
    SELECT
        cm.Repository,
        cm.CommitHash,
        m.Api,
        m.Operator,
        COUNT_BIG(o.Operator) AS OccurrenceCount
    FROM dbo.CorpusMeasurement AS cm
    CROSS JOIN dbo.Methods AS m
    LEFT JOIN dbo.Occurrences AS o
        ON  o.Repository = cm.Repository
        AND o.CommitHash = cm.CommitHash
        AND o.Api = m.Api
        AND o.Operator = m.Operator
        AND o.Kind = 'MethodCall'
    GROUP BY
        cm.Repository,
        cm.CommitHash,
        m.Api,
        m.Operator
),
RankedOperators AS
(
    SELECT
        Repository,
        CommitHash,
        Api,
        Operator,
        OccurrenceCount,

        SUM(OccurrenceCount) OVER
        (
            PARTITION BY Repository, CommitHash
        ) AS TotalOccurrenceCount,

        ROW_NUMBER() OVER
        (
            PARTITION BY Repository, CommitHash
            ORDER BY
                OccurrenceCount DESC,
                Api,
                Operator
        ) AS OperatorRank,

        SUM(OccurrenceCount) OVER
        (
            PARTITION BY Repository, CommitHash
            ORDER BY
                OccurrenceCount DESC,
                Api,
                Operator
            ROWS UNBOUNDED PRECEDING
        ) AS CumulativeOccurrenceCount

    FROM OperatorFrequencies
    WHERE OccurrenceCount > 0
),
UsedOperatorStatistics AS
(
    SELECT
        Repository,
        CommitHash,

        COUNT(*) AS UsedOperators,

        MIN(
            CASE
                WHEN CumulativeOccurrenceCount * 100.0
                     >= TotalOccurrenceCount * 50
                THEN OperatorRank
            END
        ) AS OperatorsIn50Pct,

        MIN(
            CASE
                WHEN CumulativeOccurrenceCount * 100.0
                     >= TotalOccurrenceCount * 80
                THEN OperatorRank
            END
        ) AS OperatorsIn80Pct,

        MIN(
            CASE
                WHEN CumulativeOccurrenceCount * 100.0
                     >= TotalOccurrenceCount * 90
                THEN OperatorRank
            END
        ) AS OperatorsIn90Pct,

        MIN(
            CASE
                WHEN CumulativeOccurrenceCount * 100.0
                     >= TotalOccurrenceCount * 95
                THEN OperatorRank
            END
        ) AS OperatorsIn95Pct,

        COUNT(
            CASE
                WHEN OccurrenceCount * 100.0
                     / NULLIF(TotalOccurrenceCount, 0) < 3
                THEN 1
            END
        ) AS OperatorsLessThan3Pct,

        COUNT(
            CASE
                WHEN OccurrenceCount * 100.0
                     / NULLIF(TotalOccurrenceCount, 0) < 2
                THEN 1
            END
        ) AS OperatorsLessThan2Pct,

        COUNT(
            CASE
                WHEN OccurrenceCount * 100.0
                     / NULLIF(TotalOccurrenceCount, 0) < 1
                THEN 1
            END
        ) AS OperatorsLessThan1Pct

    FROM RankedOperators
    GROUP BY
        Repository,
        CommitHash
),
CompletelyUnused AS
(
    SELECT
        Repository,
        CommitHash,
        COUNT(*) AS CompletelyUnusedOperators
    FROM OperatorFrequencies
    WHERE OccurrenceCount = 0
    GROUP BY
        Repository,
        CommitHash
)
SELECT
    u.Repository,
    u.UsedOperators,
    u.OperatorsIn50Pct,
    u.OperatorsIn80Pct,
    u.OperatorsIn90Pct,
    u.OperatorsIn95Pct,
    u.OperatorsLessThan3Pct,
    u.OperatorsLessThan2Pct,
    u.OperatorsLessThan1Pct,
    COALESCE(z.CompletelyUnusedOperators, 0) AS CompletelyUnusedOperators
FROM UsedOperatorStatistics AS u
LEFT JOIN CompletelyUnused AS z
    ON  z.Repository = u.Repository
    AND z.CommitHash = u.CommitHash
ORDER BY
    u.Repository;