using System;
using System.Diagnostics;
using System.IO;

namespace LinqCorpusAnalyzerRefactored.Utilities;

public static class GitUtilities
{
    public static string GetGitCommitHash(string root)
    {
        string? gitRoot =
            FindGitRoot(root);

        if (gitRoot is null)
        {
            Console.WriteLine(
                "WARNING: No Git repository found. " +
                "Commit hash will be recorded as N/A.");

            return "N/A";
        }

        var startInfo =
            new ProcessStartInfo
            {
                FileName = "git",
                WorkingDirectory = gitRoot,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

        startInfo.ArgumentList.Add("rev-parse");
        startInfo.ArgumentList.Add("HEAD");

        using var process =
            Process.Start(startInfo)
            ?? throw new InvalidOperationException(
                "Could not start git.");

        string output =
            process.StandardOutput
                .ReadToEnd()
                .Trim();

        string error =
            process.StandardError
                .ReadToEnd()
                .Trim();

        process.WaitForExit();

        if (process.ExitCode != 0)
        {
            Console.WriteLine(
                $"WARNING: Could not obtain Git commit hash: {error}");

            return "N/A";
        }

        return output;
    }

    public static string? FindGitRoot(string root)
    {
        DirectoryInfo? directory =
            new DirectoryInfo(root);

        while (directory is not null)
        {
            string gitPath =
                Path.Combine(
                    directory.FullName,
                    ".git");

            if (Directory.Exists(gitPath))
                return directory.FullName;

            directory =
                directory.Parent;
        }

        return null;
    }
}