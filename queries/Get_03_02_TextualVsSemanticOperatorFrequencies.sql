/*
    Get_03_02_TextualVsSemanticByOperator.sql

    For each repository and LINQ operator, reports:

    TextualOccurrences:
        Number of textual occurrences of the operator name.

    SemanticOccurrences:
        Number of semantically verified LINQ MethodCall occurrences.

    Difference:
        TextualOccurrences - SemanticOccurrences.

    DifferenceOverSemanticPct:
        ((TextualOccurrences - SemanticOccurrences)
         / SemanticOccurrences) * 100.

    The result is ordered primarily by the absolute textual excess,
    so operators responsible for the largest textual/semantic
    discrepancies appear first within each repository.

    Operators with zero occurrences are retained because Methods is
    used as the driving vocabulary table.
*/

WITH Repositories AS
(
    SELECT
        Repository,
        CommitHash
    FROM dbo.CorpusMeasurement
),
OperatorCounts AS
(
    SELECT
        r.Repository,
        r.CommitHash,
        m.Operator,

        TextualOccurrences =
        (
            SELECT COUNT_BIG(*)
            FROM dbo.TextOccurrences AS t
            WHERE t.Repository = r.Repository
              AND t.CommitHash = r.CommitHash
              AND t.Operator = m.Operator
        ),

        SemanticOccurrences =
        (
            SELECT COUNT_BIG(*)
            FROM dbo.Occurrences AS o
            WHERE o.Repository = r.Repository
              AND o.CommitHash = r.CommitHash
              AND o.Operator = m.Operator
              AND o.Kind = 'MethodCall'
        )

    FROM Repositories AS r
    CROSS JOIN
    (
        SELECT DISTINCT Operator
        FROM dbo.Methods
    ) AS m
),
Results AS
(
    SELECT
        Repository,
        Operator,
        TextualOccurrences,
        SemanticOccurrences,

        TextualOccurrences - SemanticOccurrences AS Difference,

        CAST(
            100.0 * (TextualOccurrences - SemanticOccurrences)
            / NULLIF(SemanticOccurrences, 0)
            AS decimal(10, 2)
        ) AS DifferenceOverSemanticPct

    FROM OperatorCounts
)
SELECT
    Repository,
    Operator,
    TextualOccurrences,
    SemanticOccurrences,
    Difference,
    DifferenceOverSemanticPct
FROM Results
ORDER BY
    Repository,
    Difference DESC,
    Operator;