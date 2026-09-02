/*
    Get_08_01_CrossCorpus_LinqUsageDensity.sql

    Compares LINQ method usage density across repositories
    and summarizes the combined results for all repositories.

    LINQ method occurrences are semantic MethodCall occurrences only.
    QuerySyntax occurrences are deliberately excluded.

    Density = semantic LINQ method occurrences per 1,000 C# lines.
*/

WITH LinqMethodCounts AS
(
    SELECT
        Repository,
        CommitHash,
        COUNT_BIG(*) AS TotalRepositoryLinqMethodCalls
    FROM dbo.Occurrences
    WHERE Kind = 'MethodCall'
    GROUP BY
        Repository,
        CommitHash
),
RepositoryResults AS
(
    SELECT
        cm.Repository,
        cm.CSharpFiles,
        cm.CSharpLines,
        COALESCE(lmc.TotalRepositoryLinqMethodCalls, 0)
            AS TotalRepositoryLinqMethodCalls
    FROM dbo.CorpusMeasurement AS cm
    LEFT JOIN LinqMethodCounts AS lmc
        ON  lmc.Repository = cm.Repository
        AND lmc.CommitHash = cm.CommitHash
),
CombinedResults AS
(
    SELECT
        Repository,
        CSharpFiles,
        CSharpLines,
        TotalRepositoryLinqMethodCalls,
        0 AS SortOrder
    FROM RepositoryResults

    UNION ALL

    SELECT
        'ALL_REPOSITORIES' AS Repository,
        SUM(CSharpFiles) AS CSharpFiles,
        SUM(CSharpLines) AS CSharpLines,
        SUM(TotalRepositoryLinqMethodCalls) AS TotalRepositoryLinqMethodCalls,
        1 AS SortOrder
    FROM RepositoryResults
)
SELECT
    Repository,
    CSharpFiles,
    CSharpLines,
    TotalRepositoryLinqMethodCalls,
    CAST
    (
        1000.0 * TotalRepositoryLinqMethodCalls
        / NULLIF(CSharpLines, 0)
        AS decimal(10,2)
    ) AS LinqMethodCallsPer1000CSharpLines
FROM CombinedResults
ORDER BY
    SortOrder,
    Repository;