using System.IO;
using System.Linq;
using System;
using System.Runtime.CompilerServices;

namespace LinqCorpusAnalyzerRefactored.Utilities;

public static class FileUtilities
{
    public static bool IsSourceFile(string? path)
    {
        if (string.IsNullOrEmpty(path))
            return false;

        var parts =
            path.Split(
                Path.DirectorySeparatorChar,
                Path.AltDirectorySeparatorChar);

        return !parts.Any(
            part =>
                part.Equals(
                    "obj",
                    StringComparison.OrdinalIgnoreCase)
                ||
                part.Equals(
                    "bin",
                    StringComparison.OrdinalIgnoreCase));
    }

    public static long CountLines(string file)
    {
        long count = 0;

        using var reader =
            new StreamReader(file);

        while (reader.ReadLine() is not null)
            count++;

        return count;
    }

    public static bool IsUnderRoot(
        string filePath,
        string root)
    {
        string normalizedRoot =
            Path.GetFullPath(root)
                .TrimEnd(
                    Path.DirectorySeparatorChar,
                    Path.AltDirectorySeparatorChar)
            + Path.DirectorySeparatorChar;

        string normalizedFile =
            Path.GetFullPath(filePath);

        return normalizedFile.StartsWith(
            normalizedRoot,
            StringComparison.OrdinalIgnoreCase);
    }

    public static string GetAnalyzerDirectory(
    [CallerFilePath] string sourceFilePath = "")
    {
        return Path.GetDirectoryName(sourceFilePath)!;
    }
}