/*
    08_06_04_OperatorTrigramFrequencies.sql

    Display the materialized operator trigram frequencies for ALL_Repositories
    ordered by trigram rank.
*/

USE [LinqCorpus];
GO

SELECT
    Rank,
    FirstApi,
    FirstOperator,
    SecondApi,
    SecondOperator,
    ThirdApi,
    ThirdOperator,
    TrigramCount,
    PercentageOfThisTrigramInAllTrigramsInTheCorpus
FROM Results.OperatorTrigramFrequencies
WHERE
    Repository = 'ALL_REPOSITORIES'
ORDER BY
    Rank;
GO