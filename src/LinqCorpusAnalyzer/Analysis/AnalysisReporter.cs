using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace LinqCorpusAnalyzerRefactored.Analysis;

public static class AnalysisReporter
{
    public static void Report(
        IReadOnlyDictionary<string, Microsoft.CodeAnalysis.Project> loadedProjects,
        IReadOnlySet<string> allFiles,
        IReadOnlySet<string> sharedFiles,
        IReadOnlySet<string> processedFiles,
        string processedFilesPath,
        int chainCount,
        IReadOnlyList<LinqOccurrence> occurrences,
        LinqVocabularyResults vocabularyResults)
    {
        Console.WriteLine();

        Console.WriteLine(
            "========== SUMMARY ==========");

        Console.WriteLine(
            $"Projects analyzed: {loadedProjects.Count:N0}");

        Console.WriteLine(
            $"Unique C# files analyzed: {processedFiles.Count:N0}");

        Console.WriteLine(
            $"Shared files between projects: {sharedFiles.Count:N0}");

        if (sharedFiles.Count > 0)
        {
            Console.WriteLine();

            Console.WriteLine(
                "========== SHARED SOURCE FILES ==========");

            foreach (
                string filePath in
                sharedFiles.OrderBy(
                    p => p,
                    StringComparer.OrdinalIgnoreCase))
            {
                Console.WriteLine(filePath);

                Console.WriteLine(
                    "  WARNING: file belongs to multiple projects.");

                Console.WriteLine(
                    "  It will be analyzed only under the first " +
                    "project context encountered.");
            }
        }

        Console.WriteLine(
            $"C# files discovered but not processed: " +
            $"{allFiles.Except(processedFiles).Count():N0}");

        Console.WriteLine(
            $"Processed file list: {processedFilesPath}");

        Console.WriteLine(
            $"LINQ chains detected: {chainCount:N0}");

        int actualOccurrences =
            occurrences.Count;

        Console.WriteLine();

        Console.WriteLine(
            $"Enumerable zero-occurrences: " +
            $"{vocabularyResults.EnumerableZeroCount:N0}");

        Console.WriteLine(
            $"Queryable zero-occurrences : " +
            $"{vocabularyResults.QueryableZeroCount:N0}");

        Console.WriteLine(
            $"Total zero-occurrences : " +
            $"{vocabularyResults.UnusedMembers.Count:N0}");

        Console.WriteLine();

        Console.WriteLine(
            "========== ZERO-OCCURRENCE LINQ MEMBERS ==========");

        foreach (
            var group in
            vocabularyResults.UnusedMembers.GroupBy(
                x => x.Api))
        {
            Console.WriteLine();

            Console.WriteLine(
                $"{group.Key}:");

            foreach (var item in group)
            {
                Console.WriteLine(
                    $"  {item.Operator}");
            }
        }

        int candidateNewMemberCount =
            vocabularyResults.CandidateNewMembers.Count;

        int membersCompletelyNotUsed =
            vocabularyResults.UnusedMembers.Count;

        Console.WriteLine(
            $"Actual LINQ occurrences: {actualOccurrences}");

        Console.WriteLine(
            $"Distinct LINQ members actually encountered: " +
            $"{vocabularyResults.EncounteredMembers.Count:N0}");

        Console.WriteLine(
            $"LINQ Members Completely Not Used: " +
            $"{vocabularyResults.UnusedMembers.Count:N0}");

        Console.WriteLine(
            $"Candidate new LINQ members: " +
            $"{candidateNewMemberCount:N0}");

        Console.WriteLine(
            $"Vocabulary accounting: " +
            $"{vocabularyResults.NumberEstablishedEncounteredMembers:N0} + " +
            $"{membersCompletelyNotUsed:N0} + " +
            $"{candidateNewMemberCount:N0} = " +
            $"{vocabularyResults.NumberEstablishedEncounteredMembers + membersCompletelyNotUsed + candidateNewMemberCount:N0}");

        Console.WriteLine();

        Console.WriteLine(
            "========== BY KIND / OPERATOR ==========");

        foreach (
            var group in
            occurrences
                .Where(
                    o =>
                        o.Kind !=
                            LinqKind.ZeroOccurrence_EnumerableMethod
                        &&
                        o.Kind !=
                            LinqKind.ZeroOccurrence_QueryableMethod)
                .GroupBy(
                    o =>
                        new
                        {
                            o.Kind,
                            o.Operator
                        })
                .OrderBy(
                    g => g.Key.Kind)
                .ThenBy(
                    g => g.Key.Operator))
        {
            Console.WriteLine(
                $"{group.Key.Kind,-15} " +
                $"{group.Key.Operator,-20} " +
                $"{group.Count():N0}");
        }
    }
}