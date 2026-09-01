using Microsoft.CodeAnalysis.MSBuild;
using System.Text;

using LinqCorpusAnalyzerRefactored.Utilities;
using LinqCorpusAnalyzerRefactored.Analysis;

if (args.Length != 1)
{
    Console.WriteLine(
        "Usage: LinqCorpusAnalyzer <repository-root>");
    return;
}

string root = Path.GetFullPath(args[0]);

if (!Directory.Exists(root))
{
    Console.WriteLine($"Directory not found: {root}");
    return;
}

string repositoryName = new DirectoryInfo(root).Name;
string analyzerDirectory = FileUtilities.GetAnalyzerDirectory();

string? configuredResultsRoot =
    Environment.GetEnvironmentVariable("LINQ_CORPUS_RESULTS");

string resultsRoot =
    string.IsNullOrWhiteSpace(configuredResultsRoot)
        ? Path.Combine(analyzerDirectory, "Results")
        : configuredResultsRoot!;

string resultsDirectory =
    Path.Combine(resultsRoot, repositoryName);

Directory.CreateDirectory(resultsDirectory);

Console.WriteLine(
    $"Results directory: {resultsDirectory}");

// ============================================================
// MSBuild / Roslyn setup
// ============================================================
    var msBuildInfo =
    MsBuildInitializer.Initialize();

    Console.WriteLine(
        $"dotnet: {msBuildInfo.DotNetPath}");

    Console.WriteLine(
        $"SDK version: {msBuildInfo.SdkVersion}");

    Console.WriteLine(
        $"MSBuild path: {msBuildInfo.MsBuildPath}");

    Console.WriteLine(
        $"Scanning: {root}");

    Console.WriteLine();

    using var workspace =
        MSBuildWorkspace.Create();

    workspace.RegisterWorkspaceFailedHandler(
        e =>
        {
            Console.WriteLine(
                $"WORKSPACE: {e.Diagnostic.Kind}: " +
                $"{e.Diagnostic.Message}");
        });

// ============================================================
// PHASE 1: PROJECT / FILE DISCOVERY
// ============================================================

Console.WriteLine(
        "========== PHASE 1: PROJECT / FILE DISCOVERY ==========");

    var discovery =
    new ProjectDiscovery(
        workspace,
        root);

    var discoveryResult =
        await discovery.RunAsync();

    var loadedProjects =
        discoveryResult.LoadedProjects;

    var allFiles =
        discoveryResult.AllFiles;

    var sharedFiles =
        discoveryResult.SharedFiles;

    var projectFiles =
        discoveryResult.ProjectFiles;

    string commitHash =
        CorpusMeasurement.CreateResults(
            root,
            resultsDirectory,
            repositoryName);

    string projectFilesPath =
        Path.Combine(
            resultsDirectory,
            "ProjectFiles.csv");

    ProjectFilesWriter.Write(
        projectFilesPath,
        repositoryName,
        commitHash,
        projectFiles);

    Console.WriteLine();

    Console.WriteLine(
        $"Projects to be analyzed: {loadedProjects.Count:N0}");

    Console.WriteLine(
        $"Unique C# files discovered: {allFiles.Count:N0}");

    Console.WriteLine(
        $"Shared C# files: {sharedFiles.Count:N0}");

    if (loadedProjects.Count == 0)
    {
        Console.WriteLine();

        Console.WriteLine(
            "ERROR: No projects were successfully loaded.");

        Console.WriteLine(
            "Semantic analysis cannot proceed.");

        return;
    }

    // ============================================================
    // Prepare semantic analysis output
    // ============================================================

    string occurrencesPath =
        Path.Combine(
            resultsDirectory,
            "occurrences.csv");

    using var occWriter =
        new StreamWriter(
            occurrencesPath,
            append: false,
            Encoding.UTF8);

    occWriter.WriteLine(
        "Repository,Project,Operator,API,Kind,File,Line");

    string chainsPath =
        Path.Combine(
            resultsDirectory,
            "chains.csv");

    using var chainWriter =
        new StreamWriter(
            chainsPath,
            append: false,
            Encoding.UTF8);

    chainWriter.WriteLine(
        "ChainId,Repository,Project," +
        "LeftmostPosition,RightmostPosition,Methods");



// ============================================================
// PHASE 2: SEMANTIC ANALYSIS
// ============================================================

Console.WriteLine();

    var semanticAnalyzer =
    new SemanticAnalyzer(
        loadedProjects,
        allFiles,
        sharedFiles,
        root,
        repositoryName);

    var semanticResults =
        await semanticAnalyzer.RunAsync(
            occWriter,
            chainWriter);

    var processedFiles =
        semanticResults.ProcessedFiles;

    var occurrences =
        semanticResults.Occurrences;

    int chainCount =
        semanticResults.ChainCount;

// ============================================================
// Save the set of files processed by semantic analysis.
// This file is used by the textual analyzer so that both
// analyses operate on the same physical file set.
// ============================================================

string processedFilesPath =
        Path.Combine(
            resultsDirectory,
            "processed-files.txt");

    File.WriteAllLines(
        processedFilesPath,
        processedFiles.OrderBy(
            p => p,
            StringComparer.OrdinalIgnoreCase));

    occWriter.Close();
    chainWriter.Close();

    var vocabularyResults =
    LinqVocabularyAnalysis.GetLinqVocabularyResults(
        analyzerDirectory,
        occurrences);

    AnalysisReporter.Report(
        loadedProjects,
        allFiles,
        sharedFiles,
        processedFiles,
        processedFilesPath,
        chainCount,
        occurrences,
        vocabularyResults);
