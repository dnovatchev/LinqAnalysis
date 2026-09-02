/*
    Get_08_05_03_RankFrequencyRegression.sql

    Purpose:
        Fit the rank-frequency relationship for LINQ operators
        within each repository and for the combined corpus.

    Method:
        For each repository, rank LINQ operators by decreasing
        occurrence count.

        The ALL_REPOSITORIES ranking is computed independently from
        the combined occurrence counts across all repositories.

        Only operators with at least one occurrence are included.

        Perform a linear regression on the log-log transformation:

            Y = log10(OccurrenceCount)
            X = log10(Rank)

        Therefore:

            Y = Slope * X + Intercept

        StraightLineFitR2 is the coefficient of determination (R²)
        and measures how closely the observed log-log points follow
        a straight line.

    Notes:
        - Ties are ordered by Methods.Id descending, consistently with
          Get_08_05_CrossCorpus_LinqOperatorFrequencyRankings.sql and
          Get_08_05_02_RankFrequencyAnalysis.sql.
        - Zero-occurrence methods are excluded because log10(0)
          is undefined.
        - ALL_REPOSITORIES is fitted independently; repository-level
          regression parameters are not averaged.
*/

USE [LinqCorpus];
GO

WITH MethodFrequencies AS
(
    SELECT
        o.Repository,
        o.Api,
        o.Operator,
        COUNT_BIG(*) AS OccurrenceCount,
        MAX(m.Id) AS MethodId
    FROM dbo.Occurrences AS o
    INNER JOIN dbo.Methods AS m
        ON  m.Api = o.Api
        AND m.Operator = o.Operator
    WHERE o.Kind = 'MethodCall'
    GROUP BY
        o.Repository,
        o.Api,
        o.Operator
),
RepositoryMethodFrequencies AS
(
    SELECT
        Repository,
        Api,
        Operator,
        MethodId,
        OccurrenceCount
    FROM MethodFrequencies
    WHERE OccurrenceCount > 0
),
AllRepositoryMethodFrequencies AS
(
    SELECT
        'ALL_REPOSITORIES' AS Repository,
        Api,
        Operator,
        MethodId,
        SUM(OccurrenceCount) AS OccurrenceCount
    FROM MethodFrequencies
    GROUP BY
        Api,
        Operator,
        MethodId
    HAVING SUM(OccurrenceCount) > 0
),
CombinedMethodFrequencies AS
(
    SELECT
        Repository,
        Api,
        Operator,
        MethodId,
        OccurrenceCount
    FROM RepositoryMethodFrequencies

    UNION ALL

    SELECT
        Repository,
        Api,
        Operator,
        MethodId,
        OccurrenceCount
    FROM AllRepositoryMethodFrequencies
),
RankedMethods AS
(
    SELECT
        Repository,
        Api,
        Operator,
        MethodId,
        OccurrenceCount,

        ROW_NUMBER() OVER
        (
            PARTITION BY Repository
            ORDER BY
                OccurrenceCount DESC,
                MethodId DESC,
                Api,
                Operator
        ) AS Rank

    FROM CombinedMethodFrequencies
),
LogValues AS
(
    SELECT
        Repository,
        Rank,
        OccurrenceCount,

        LOG10(CAST(Rank AS float)) AS X,
        LOG10(CAST(OccurrenceCount AS float)) AS Y

    FROM RankedMethods
),
Means AS
(
    SELECT
        Repository,
        COUNT_BIG(*) AS NumberOfRankedMethods,

        MIN(Rank) AS MinRank,
        MAX(Rank) AS MaxRank,

        MIN(OccurrenceCount) AS MinOccurrenceCount,
        MAX(OccurrenceCount) AS MaxOccurrenceCount,

        AVG(X) AS MeanX,
        AVG(Y) AS MeanY

    FROM LogValues
    GROUP BY
        Repository
),
RegressionSums AS
(
    SELECT
        l.Repository,

        SUM(
            (l.X - m.MeanX)
            * (l.Y - m.MeanY)
        ) AS SumXY,

        SUM(
            POWER(l.X - m.MeanX, 2)
        ) AS SumXX,

        SUM(
            POWER(l.Y - m.MeanY, 2)
        ) AS SumYY

    FROM LogValues AS l
    INNER JOIN Means AS m
        ON m.Repository = l.Repository

    GROUP BY
        l.Repository
)
SELECT
    m.Repository,
    m.NumberOfRankedMethods,

    CAST(
        s.SumXY / NULLIF(s.SumXX, 0)
        AS decimal(18,6)
    ) AS Slope,

    CAST(
        m.MeanY
        - (
            s.SumXY / NULLIF(s.SumXX, 0)
          ) * m.MeanX
        AS decimal(18,6)
    ) AS Intercept,

    CAST(
        POWER(s.SumXY, 2)
        / NULLIF(s.SumXX * s.SumYY, 0)
        AS decimal(18,6)
    ) AS StraightLineFitR2,

    m.MinRank,
    m.MaxRank,
    m.MinOccurrenceCount,
    m.MaxOccurrenceCount

FROM Means AS m
INNER JOIN RegressionSums AS s
    ON s.Repository = m.Repository

ORDER BY
    CASE
        WHEN m.Repository = 'ALL_REPOSITORIES' THEN 1
        ELSE 0
    END,
    m.Repository;
GO