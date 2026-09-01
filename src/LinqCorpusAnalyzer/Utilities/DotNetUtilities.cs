using System.Diagnostics;

namespace LinqCorpusAnalyzerRefactored.Utilities;

public static class DotNetUtilities
{
    public static string GetDotNetVersion(
        string dotnetPath)
    {
        var psi =
            new ProcessStartInfo
            {
                FileName = dotnetPath,
                Arguments = "--version",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

        using var process =
            Process.Start(psi)
            ?? throw new InvalidOperationException(
                "Could not start dotnet.");

        string version =
            process.StandardOutput
                .ReadToEnd()
                .Trim();

        process.WaitForExit();

        if (process.ExitCode != 0 ||
            string.IsNullOrWhiteSpace(version))
        {
            throw new InvalidOperationException(
                "Could not determine dotnet SDK version.");
        }

        return version;
    }

    public static string GetAnalyzerSdkVersion()
    {
        var startInfo =
            new ProcessStartInfo
            {
                FileName = "dotnet",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

        startInfo.ArgumentList.Add("--version");

        using var process =
            Process.Start(startInfo)
            ?? throw new InvalidOperationException(
                "Could not start dotnet.");

        string output =
            process.StandardOutput
                .ReadToEnd()
                .Trim();

        process.WaitForExit();

        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException(
                "Could not determine .NET SDK version.");
        }

        return output;
    }
}