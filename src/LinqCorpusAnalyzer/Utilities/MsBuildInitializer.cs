using Microsoft.Build.Locator;
using System.IO;
using System;

namespace LinqCorpusAnalyzerRefactored.Utilities;

public static class MsBuildInitializer
{
    public static MsBuildInfo Initialize()
    {
        string dotnetDirectory =
            Path.Combine(
                Environment.GetFolderPath(
                    Environment.SpecialFolder.ProgramFiles),
                "dotnet");

        Console.WriteLine(
            $"Using system .NET installation: {dotnetDirectory}");

        string dotnetPath =
            Path.Combine(
                dotnetDirectory,
                "dotnet.exe");

        if (!File.Exists(dotnetPath))
        {
            throw new InvalidOperationException(
                $"Could not locate dotnet.exe: {dotnetPath}");
        }

        string sdkVersion =
            DotNetUtilities.GetDotNetVersion(dotnetPath);

        string msbuildPath =
            Path.Combine(
                dotnetDirectory,
                "sdk",
                sdkVersion);

        if (!Directory.Exists(msbuildPath))
        {
            throw new InvalidOperationException(
                $"MSBuild SDK directory not found: {msbuildPath}");
        }

        Environment.SetEnvironmentVariable(
            "DOTNET_ROOT",
            dotnetDirectory);

        Environment.SetEnvironmentVariable(
            "DOTNET_ROOT(x64)",
            dotnetDirectory);

        Console.WriteLine(
            $"DOTNET_ROOT: " +
            $"{Environment.GetEnvironmentVariable("DOTNET_ROOT")}");

        MSBuildLocator.RegisterMSBuildPath(msbuildPath);

        return new MsBuildInfo(
            dotnetPath,
            sdkVersion,
            msbuildPath);
    }
}