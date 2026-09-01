using LinqCorpusAnalyzerRefactored.Utilities;

using System.Collections.Generic;
using System.IO;
using System.Text;

namespace LinqCorpusAnalyzerRefactored.Analysis;

public static class ProjectFilesWriter
{
    public static void Write(
        string path,
        string repositoryName,
        string commitHash,
        IReadOnlyList<(string Project, string FilePath)> projectFiles)
    {
        using var writer =
            new StreamWriter(
                path,
                append: false,
                Encoding.UTF8);

        writer.WriteLine(
            "Repository,CommitHash,Project,FilePath");

        foreach (var projectFile in projectFiles)
        {
            writer.WriteLine(
                string.Join(
                    ",",
                    CsvUtilities.CsvField(repositoryName),
                    CsvUtilities.CsvField(commitHash),
                    CsvUtilities.CsvField(projectFile.Project),
                    CsvUtilities.CsvField(projectFile.FilePath)));
        }
    }
}