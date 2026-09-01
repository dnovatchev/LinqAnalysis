using System.Text;
using LinqCorpusTextAnalyzerRefactored.Analysis;

if (args.Length != 2)
{
    Console.WriteLine(
        "Usage: LinqCorpusTextAnalyzer " +
        "<repository-directory> <processed-files.txt>");
    return;
}

string root = Path.GetFullPath(args[0]);

string processedFilesPath =
    Path.GetFullPath(args[1]);
if (!Directory.Exists(root))
{
    Console.WriteLine(
        $"Directory not found: {root}");
    return;
}

if (!File.Exists(processedFilesPath))
{
    Console.WriteLine(
        $"Processed-files list not found: {processedFilesPath}");
    return;
}

string repository =
    new DirectoryInfo(root).Name;

string resultsDirectory =
    Path.GetDirectoryName(processedFilesPath)!;

Directory.CreateDirectory(resultsDirectory);

string occurrencesPath =
    Path.Combine(
        resultsDirectory,
        "text-occurrences.csv");

Console.WriteLine(
    $"Scanning: {root}");

Console.WriteLine(); 

var runner =
    new TextAnalysisRunner(repository);

var result =
    runner.Run(
        processedFilesPath,
        occurrencesPath);

var occurrences = result.Occurrences;

var filesToAnalyze = result.FilesToAnalyze;

var analyzedFiles = result.AnalyzedFiles;

Console.WriteLine(
    "========== SUMMARY ==========");

Console.WriteLine(
    $"C# files specified by semantic analyzer: " +
    $"{filesToAnalyze.Count:N0}");

Console.WriteLine(
    $"C# files analyzed: {analyzedFiles.Count:N0}");

Console.WriteLine(
    $"C# files not analyzed: " +
    $"{filesToAnalyze.Except(analyzedFiles).Count():N0}");
Console.WriteLine(
    $"LINQ name occurrences: {occurrences.Count:N0}");
Console.WriteLine(
    $"Processed-files list: {processedFilesPath}");

Console.WriteLine();
Console.WriteLine("========== BY OPERATOR ==========");

foreach (var group in occurrences
    .GroupBy(o => o.Member)
    .OrderBy(g => g.Key))
{
    Console.WriteLine(
        $"{group.Key,-25} {group.Count():N0}");
}
