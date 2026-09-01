using System.Collections.Generic;
using System.IO;
using System;

namespace LinqCorpusAnalyzerRefactored.Utilities;

public static class LinqApiHistoryReader
{
    public static List<LinqApiHistoryEntry> Read(
        string fileName)
    {
        if (!File.Exists(fileName))
        {
            throw new FileNotFoundException(
                "LINQ API history file was not found.",
                fileName);
        }

        var result =
            new List<LinqApiHistoryEntry>();

        foreach (
            var line in
            File.ReadLines(fileName).Skip(1))
        {
            if (string.IsNullOrWhiteSpace(line))
                continue;

            var fields =
                line.Split(',');

            if (fields.Length != 5)
            {
                throw new InvalidDataException(
                    $"Invalid LinqApiHistory.csv row:" +
                    $"{Environment.NewLine}{line}");
            }

            result.Add(
                new LinqApiHistoryEntry(
                    fields[0].Trim(),
                    fields[1].Trim(),
                    fields[2].Trim(),
                    fields[3].Trim(),
                    fields[4].Trim()));
        }

        return result;
    }
}