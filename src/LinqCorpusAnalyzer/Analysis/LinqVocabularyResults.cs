namespace LinqCorpusAnalyzerRefactored.Analysis;

public sealed record LinqVocabularyResults(
    HashSet<(string Api, string Operator)> EncounteredMembers,
    HashSet<(string Api, string Operator)> UnusedMembers,
    HashSet<(string Api, string Operator)> CandidateNewMembers,
    int NumberEstablishedEncounteredMembers,
    int EnumerableZeroCount,
    int QueryableZeroCount
);
