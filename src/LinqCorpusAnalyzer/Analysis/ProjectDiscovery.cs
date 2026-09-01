using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.MSBuild;

using LinqCorpusAnalyzerRefactored.Utilities;
namespace LinqCorpusAnalyzerRefactored.Analysis;

public sealed class ProjectDiscovery
{
    private readonly MSBuildWorkspace workspace;
    private readonly string root;

    public ProjectDiscovery(
        MSBuildWorkspace workspace,
        string root)
    {
        this.workspace = workspace;
        this.root = root;
    }

    public async Task<ProjectDiscoveryResult> RunAsync()
    {
        var allFiles =
            new HashSet<string>(
                StringComparer.OrdinalIgnoreCase);

        var sharedFiles =
            new HashSet<string>(
                StringComparer.OrdinalIgnoreCase);

        var projectFiles =
            new List<(string Project, string FilePath)>();

        var loadedProjects =
            new Dictionary<string, Project>(
                StringComparer.OrdinalIgnoreCase);

        var projectPaths =
            Directory.EnumerateFiles(
                    root,
                    "*.csproj",
                    SearchOption.AllDirectories)
                .OrderBy(
                    p => Path.GetRelativePath(root, p),
                    StringComparer.OrdinalIgnoreCase)
                .ToList();

        if (projectPaths.Count == 0)
        {
            Console.WriteLine(
                "ERROR: No .csproj files found.");

            return new ProjectDiscoveryResult(
                loadedProjects,
                allFiles,
                sharedFiles,
                projectFiles);
        }

        Console.WriteLine(
            $"Projects found: {projectPaths.Count:N0}");

        Console.WriteLine();

        foreach (string projectPath in projectPaths)
        {
            Console.WriteLine(
                $"Loading: {projectPath}");

            try
            {
                Project project;

                if (loadedProjects.TryGetValue(
                        projectPath,
                        out var alreadyLoadedProject))
                {
                    Console.WriteLine(
                        $"Already processed: " +
                        $"{alreadyLoadedProject.Name}");

                    continue;
                }

                var existingProject =
                    workspace.CurrentSolution.Projects
                        .FirstOrDefault(
                            p =>
                                string.Equals(
                                    p.FilePath,
                                    projectPath,
                                    StringComparison.OrdinalIgnoreCase));

                if (existingProject != null)
                {
                    Console.WriteLine(
                        $"Reusing workspace project: " +
                        $"{existingProject.Name}");

                    project = existingProject;
                }
                else
                {
                    project =
                        await workspace.OpenProjectAsync(
                            projectPath);
                }

                loadedProjects.Add(
                    projectPath,
                    project);

                foreach (var document in project.Documents)
                {
                    if (!document.SupportsSyntaxTree ||
                        !FileUtilities.IsSourceFile(
                            document.FilePath))
                    {
                        continue;
                    }

                    string filePath =
                        Path.GetFullPath(
                            document.FilePath!);

                    if (!FileUtilities.IsUnderRoot(
                            filePath,
                            root))
                    {
                        continue;
                    }

                    if (!allFiles.Add(filePath))
                    {
                        // This physical source file has already
                        // occurred in another project.
                        sharedFiles.Add(filePath);
                    }

                    projectFiles.Add(
                        (project.Name, filePath));
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine(
                    $"ERROR loading project: {projectPath}");

                Console.WriteLine(
                    $"  {ex.Message}");
            }
        }

        return new ProjectDiscoveryResult(
            loadedProjects,
            allFiles,
            sharedFiles,
            projectFiles);
    }
}