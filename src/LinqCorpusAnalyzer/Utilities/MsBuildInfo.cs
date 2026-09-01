namespace LinqCorpusAnalyzerRefactored.Utilities;

public sealed record MsBuildInfo(
    string DotNetPath,
    string SdkVersion,
    string MsBuildPath);