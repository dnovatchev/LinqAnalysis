using System.IO;
using System;
using System.Collections.Generic;

using LinqCorpusAnalyzerRefactored.Utilities;

namespace LinqCorpusAnalyzerRefactored.Analysis;

internal static class LinqVocabularyAnalysis
{
    internal static LinqVocabularyResults 
        GetLinqVocabularyResults(string analyzerDirectory, IReadOnlyList<LinqOccurrence> occurrences)
    {
        string historicalDataDirectory =
            Path.Combine(
                analyzerDirectory,
                "HistoricalData");

        string apiHistoryFile =
            Path.Combine(
                historicalDataDirectory,
                "LinqApiHistory.csv");

        Console.WriteLine(
            $"LINQ API history: {apiHistoryFile}");

        var apiHistory =
            LinqApiHistoryReader.Read(apiHistoryFile);

        var vocabulary =
            apiHistory
                .Where(
                    h =>
                        !string.IsNullOrWhiteSpace(h.Api))
                .Where(
                    h =>
                        !string.IsNullOrWhiteSpace(h.Operator))
                .Where(
                    h =>
                        h.Api.Equals(
                            "Enumerable",
                            StringComparison.Ordinal)
                        ||
                        h.Api.Equals(
                            "Queryable",
                            StringComparison.Ordinal))
                .Select(
                    h =>
                        (
                            Api: h.Api,
                            Operator: h.Operator
                        ))
                .Distinct()
                .ToHashSet();
            var unusedMembers =
                GetZeroOccurrenceMembers(
                    occurrences,
                    vocabulary);
            var encounteredMembers =
                occurrences
                    .Where(o => o.Api != null)
                    .Select(
                        o =>
                            (
                                Api: o.Api!,
                                Operator: o.Operator
                            ))
                    .ToHashSet();

            var candidateNewMembers =
                encounteredMembers
                    .Except(vocabulary)
                    .ToHashSet();

            int establishedEncounteredMembers =
                encounteredMembers
                    .Intersect(vocabulary)
                    .Count();

            int enumerableZeroCount =
                unusedMembers.Count(
                    x => x.Api == "Enumerable");

            int queryableZeroCount =
                unusedMembers.Count(
                    x => x.Api == "Queryable");


       return new LinqVocabularyResults(encounteredMembers, unusedMembers, candidateNewMembers,
           establishedEncounteredMembers, enumerableZeroCount, queryableZeroCount);
    }

    static HashSet<(string Api, string Operator)>
    GetZeroOccurrenceMembers(
        IEnumerable<LinqOccurrence> occurrences,
        HashSet<(string Api, string Operator)> vocabulary)
    {
        // --------------------------------------------------------
        // Determine which LINQ API members were actually observed.
        // Zero-occurrence entries are no longer part of occurrences.
        // Query-syntax occurrences have Api == null and therefore
        // cannot match an Enumerable/Queryable vocabulary member.
        // --------------------------------------------------------

        var observed =
            occurrences
                .Select(
                    o =>
                        (
                            Api: o.Api!,
                            Operator: o.Operator
                        ))
                .ToHashSet();

        // --------------------------------------------------------
        // Find vocabulary members for which no occurrence was
        // observed in the corpus.
        // --------------------------------------------------------

        return vocabulary
            .Where(v => !observed.Contains(v))
            .ToHashSet();
    }
}
