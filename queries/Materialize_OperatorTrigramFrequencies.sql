USE [LinqCorpus];
GO

/*
    Refresh the materialized trigram-frequency results.

    The source view includes:
        - one result set for each Repository + CommitHash
        - ALL_REPOSITORIES rows

    The target table already exists.
*/
TRUNCATE TABLE Results.OperatorTrigramFrequencies;
GO

INSERT INTO Results.OperatorTrigramFrequencies
(
    Repository,
    CommitHash,
    Rank,
    FirstApi,
    FirstOperator,
    SecondApi,
    SecondOperator,
    ThirdApi,
    ThirdOperator,
    TrigramCount,
    PercentageOfThisTrigramInAllTrigramsInTheCorpus
)
SELECT
    Repository,
    CommitHash,
    Rank,
    FirstApi,
    FirstOperator,
    SecondApi,
    SecondOperator,
    ThirdApi,
    ThirdOperator,
    TrigramCount,
    PercentageOfThisTrigramInAllTrigramsInTheCorpus
FROM dbo.vw_OperatorTrigramFrequencies;
GO