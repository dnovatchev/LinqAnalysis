using System.Collections.Generic;
using System.IO;
using System.Linq;
using System;
using System.Text;

namespace LinqCorpusTextAnalyzerRefactored.Analysis;

public static class TextAnalyzer
{
    private static readonly HashSet<string> LinqMembers =
        new(StringComparer.Ordinal)
        {
            "Aggregate",
            "AggregateBy",
            "All",
            "Any",
            "Append",
            "AsEnumerable",
            "AsQueryable",
            "Average",
            "Cast",
            "Chunk",
            "Concat",
            "Contains",
            "Count",
            "CountBy",
            "DefaultIfEmpty",
            "Distinct",
            "DistinctBy",
            "ElementAt",
            "ElementAtOrDefault",
            "Empty",
            "Except",
            "ExceptBy",
            "First",
            "FirstOrDefault",
            "FullJoin",
            "GroupBy",
            "GroupJoin",
            "Index",
            "InfiniteSequence",
            "Intersect",
            "IntersectBy",
            "Join",
            "Last",
            "LastOrDefault",
            "LeftJoin",
            "LongCount",
            "Max",
            "MaxBy",
            "Min",
            "MinBy",
            "OfType",
            "Order",
            "OrderBy",
            "OrderByDescending",
            "OrderDescending",
            "Prepend",
            "Range",
            "Repeat",
            "Reverse",
            "RightJoin",
            "Select",
            "SelectMany",
            "Sequence",
            "SequenceEqual",
            "Shuffle",
            "Single",
            "SingleOrDefault",
            "Skip",
            "SkipLast",
            "SkipWhile",
            "Sum",
            "Take",
            "TakeLast",
            "TakeWhile",
            "ThenBy",
            "ThenByDescending",
            "ToArray",
            "ToDictionary",
            "ToHashSet",
            "ToList",
            "ToLookup",
            "TryGetNonEnumeratedCount",
            "Union",
            "UnionBy",
            "Where",
            "Zip"
        };

    public static void AnalyzeFile(
        string text,
        string filePath,
        string repository,
        List<TextOccurrence> occurrences,
        StreamWriter writer)
    {
        foreach (MethodCall match in FindMethodCalls(text))
        {
            string memberName = match.Member;

            if (!LinqMembers.Contains(memberName))
                continue;

            int line =
                GetLineNumber(
                    text,
                    match.Position);

            var occurrence =
                new TextOccurrence(
                    memberName,
                    filePath,
                    line);

            occurrences.Add(occurrence);

            WriteOccurrenceLine(
                writer,
                repository,
                filePath,
                line.ToString(),
                memberName);
        }
    }

    private static IEnumerable<MethodCall> FindMethodCalls(
        string text)
    {
        int position = 0;

        while (position < text.Length)
        {
            if (!IsIdentifierStart(text[position]))
            {
                position++;
                continue;
            }

            int start = position;

            position++;

            while (position < text.Length &&
                   IsIdentifierPart(text[position]))
            {
                position++;
            }

            string identifier =
                text[start..position];

            // We only care about LINQ member names.
            //
            // This also prevents us from doing generic
            // bracket scanning for unrelated identifiers.
            if (!LinqMembers.Contains(identifier))
                continue;

            int afterIdentifier = position;

            while (position < text.Length &&
                   char.IsWhiteSpace(text[position]))
            {
                position++;
            }

            // Ordinary method call:
            //
            // Empty(...)
            // Where(...)
            //
            if (position < text.Length &&
                text[position] == '(')
            {
                yield return new MethodCall(
                    identifier,
                    start);

                position = afterIdentifier;
                continue;
            }

            // Possible generic method call.
            //
            // We require the character immediately after '<' to be a
            // valid identifier-start character. This distinguishes generic
            // type arguments from comparison operators such as < and <=.
            //
            // Empty<T>(...)
            // Empty<List<string>>(...)
            if (position < text.Length &&
                text[position] == '<' &&
                position + 1 < text.Length &&
                IsIdentifierStart(text[position + 1]))
            {
                int closingAngle =
                    FindMatchingAngleBracket(
                        text,
                        position);

                if (closingAngle >= 0)
                {
                    position = closingAngle + 1;

                    while (position < text.Length &&
                           char.IsWhiteSpace(text[position]))
                    {
                        position++;
                    }

                    if (position < text.Length &&
                        text[position] == '(')
                    {
                        yield return new MethodCall(
                            identifier,
                            start);
                    }
                }
            }
        }
    }

    private static int FindMatchingAngleBracket(
        string text,
        int openingPosition)
    {
        int depth = 0;

        for (int i = openingPosition;
             i < text.Length;
             i++)
        {
            switch (text[i])
            {
                case '<':
                    depth++;
                    break;

                case '>':
                    depth--;

                    if (depth == 0)
                        return i;

                    break;
            }
        }

        return -1;
    }

    private static bool IsIdentifierStart(
        char c)
    {
        return
            c == '_' ||
            char.IsLetter(c);
    }

    private static bool IsIdentifierPart(
        char c)
    {
        return
            c == '_' ||
            char.IsLetterOrDigit(c);
    }

    private static int GetLineNumber(
        string text,
        int position)
    {
        int line = 1;

        for (int i = 0;
             i < position;
             i++)
        {
            if (text[i] == '\n')
                line++;
        }

        return line;
    }

    private static string CsvField(
        string value)
    {
        if (value.Contains('"') ||
            value.Contains(',') ||
            value.Contains('\r') ||
            value.Contains('\n'))
        {
            return "\"" +
                   value.Replace(
                       "\"",
                       "\"\"") +
                   "\"";
        }

        return value;
    }

    private static void WriteOccurrenceLine(
        StreamWriter writer,
        string repository,
        string file,
        string line,
        string memberName)
    {
        writer.WriteLine(
            string.Join(",",
                CsvField(repository),
                CsvField(file),
                CsvField(line),
                CsvField(memberName)));
    }
}

public record TextOccurrence(
    string Member,
    string File,
    int Line);

public record MethodCall(
    string Member,
    int Position);