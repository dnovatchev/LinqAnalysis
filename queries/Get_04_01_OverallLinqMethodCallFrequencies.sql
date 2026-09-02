/*
    Get_04_01_OverallLinqMethodCallFrequencies.sql

    Overall frequency of semantic LINQ method calls across
    all repositories.

    One row is reported for each LINQ member in the vocabulary.

    Only semantic LINQ method calls are included:
        Occurrences.Kind = 'MethodCall'

    Results are ranked by descending occurrence count.
*/

WITH MethodOccurrences AS
(
    SELECT
        o.Api,
        o.Operator,
        m.Id AS MethodId,
        COUNT_BIG(*) AS OccurrenceCount
    FROM dbo.Occurrences AS o
    INNER JOIN dbo.Methods AS m
        ON  m.Api = o.Api
        AND m.Operator = o.Operator
    WHERE o.Kind = 'MethodCall'
    GROUP BY
        o.Api,
        o.Operator,
        m.Id
),
TotalOccurrences AS
(
    SELECT
        SUM(OccurrenceCount) AS TotalOccurrenceCount
    FROM MethodOccurrences
)
SELECT
    mo.Api,
    mo.Operator,
    mo.OccurrenceCount,
    CAST
    (
        100.0 * mo.OccurrenceCount
        / NULLIF(t.TotalOccurrenceCount, 0)
        AS decimal(10,2)
    ) AS PercentageOfTotal,
    ROW_NUMBER() OVER
    (
        ORDER BY
            mo.OccurrenceCount DESC,
            mo.MethodId
    ) AS FrequencyRank
FROM MethodOccurrences AS mo
CROSS JOIN TotalOccurrences AS t
ORDER BY
    FrequencyRank;