using System.IO;
using System;
using System.Text;

using LinqCorpusAnalyzerRefactored.Utilities;

namespace LinqCorpusAnalyzerRefactored.Analysis;

internal static class CorpusMeasurement
{
    public static string CreateResults(
        string root,
        string resultsDirectory,
        string repositoryName)
    {
        string path =
            Path.Combine(
                resultsDirectory,
                "CorpusMeasurement.csv");

        string commitHash =
            GitUtilities.GetGitCommitHash(root);

        if (File.Exists(path))
        {
            Console.WriteLine(
                $"Corpus measurement already exists: {path}");

            return commitHash;
        }

        Console.WriteLine();

        Console.WriteLine(
            "========== CORPUS MEASUREMENT ==========");

        string analyzerSdk =
            DotNetUtilities.GetAnalyzerSdkVersion();

        var allFiles =
            Directory
                .EnumerateFiles(
                    root,
                    "*",
                    SearchOption.AllDirectories)
                .Where(FileUtilities.IsSourceFile)
                .ToList();

        int totalFiles =
            allFiles.Count;

        int csprojFiles =
            allFiles.Count(
                f =>
                    f.EndsWith(
                        ".csproj",
                        StringComparison.OrdinalIgnoreCase));

        var csharpFiles =
            allFiles
                .Where(
                    f =>
                        f.EndsWith(
                            ".cs",
                            StringComparison.OrdinalIgnoreCase))
                .ToList();

        int csharpFileCount =
            csharpFiles.Count;

        long csharpBytes =
            csharpFiles.Sum(
                f =>
                    new FileInfo(f).Length);

        double csharpMB =
            csharpBytes /
            (1024.0 * 1024.0);

        long csharpLines =
            csharpFiles.Sum(
                FileUtilities.CountLines);

        using var writer =
            new StreamWriter(
                path,
                append: false,
                Encoding.UTF8);

        writer.WriteLine(
            "Repository,CommitHash,AnalyzerSDK," +
            "TotalFiles,CsprojFiles,CSharpFiles," +
            "CSharpBytes,CSharpMB,CSharpLines");

        writer.WriteLine(
            string.Join(
                ",",
                CsvUtilities.CsvField(repositoryName),
                CsvUtilities.CsvField(commitHash),
                CsvUtilities.CsvField(analyzerSdk),
                totalFiles,
                csprojFiles,
                csharpFileCount,
                csharpBytes,
                csharpMB.ToString("F2"),
                csharpLines));

        Console.WriteLine(
            $"Corpus measurement written: {path}");

        return commitHash;
    }
}