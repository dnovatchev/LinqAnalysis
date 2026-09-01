using System.Text;

namespace LinqCorpusTextAnalyzerRefactored.Analysis;

public sealed class TextAnalysisRunner
{
    private readonly string _repository;

    public TextAnalysisRunner(
        string repository)
    {
        _repository = repository;
    }

    public TextAnalysisResult Run(
        string processedFilesPath,
        string occurrencesPath)
    {
        var occurrences =
            new List<TextOccurrence>();

        var filesToAnalyze =
            File.ReadLines(processedFilesPath)
                .Where(line => !string.IsNullOrWhiteSpace(line))
                .Select(Path.GetFullPath)
                .ToHashSet(
                    StringComparer.OrdinalIgnoreCase);

        var analyzedFiles =
            new HashSet<string>(
                StringComparer.OrdinalIgnoreCase);

        var files =
            filesToAnalyze
                .OrderBy(
                    p => p,
                    StringComparer.OrdinalIgnoreCase)
                .ToList();

        using var writer =
            new StreamWriter(
                occurrencesPath,
                append: false,
                Encoding.UTF8);

        writer.WriteLine(
            "Repository,File,Line,Operator");

        foreach (string fullPath in files)
        {
            try
            {
                string text =
                    File.ReadAllText(fullPath);

                TextAnalyzer.AnalyzeFile(
                    text,
                    fullPath,
                    _repository,
                    occurrences,
                    writer);

                analyzedFiles.Add(fullPath);
                writer.Flush();
            }
            catch (Exception ex)
            {
                Console.WriteLine(
                    $"ERROR: {fullPath}");

                Console.WriteLine(
                    $"       {ex.Message}");
            }
        }

        return new TextAnalysisResult(
            filesToAnalyze,
            analyzedFiles,
            occurrences);
    }
}

public sealed record TextAnalysisResult(
    IReadOnlySet<string> FilesToAnalyze,
    IReadOnlySet<string> AnalyzedFiles,
    IReadOnlyList<TextOccurrence> Occurrences);