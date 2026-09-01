using Microsoft.CodeAnalysis;

namespace LinqCorpusAnalyzerRefactored.Analysis;

public sealed record ProjectDiscoveryResult(
    IReadOnlyDictionary<string, Project> LoadedProjects,
    IReadOnlySet<string> AllFiles,
    IReadOnlySet<string> SharedFiles,
    IReadOnlyList<(string Project, string FilePath)> ProjectFiles);