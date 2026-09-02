USE [LinqCorpus];
GO

SELECT *
FROM dbo.vw_OperatorTrigramContinuations
ORDER BY
    Repository,
    CommitHash,
    FirstApi,
    FirstOperator,
    SecondApi,
    SecondOperator,
    ThirdApi,
    ThirdOperator,
    RankOfThisContinuation;
GO