using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp.Syntax;

using LinqCorpusAnalyzerRefactored.Utilities;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using System;

namespace LinqCorpusAnalyzerRefactored.Analysis;

internal sealed class SemanticAnalyzer
{
    private readonly IReadOnlyDictionary<string, Project> loadedProjects;
    private readonly IReadOnlySet<string> allFiles;
    private readonly IReadOnlySet<string> sharedFiles;
    private readonly string root;
    private readonly string repositoryName;

    public SemanticAnalyzer(
        IReadOnlyDictionary<string, Project> loadedProjects,
        IReadOnlySet<string> allFiles,
        IReadOnlySet<string> sharedFiles,
        string root,
        string repositoryName)
    {
        this.loadedProjects = loadedProjects;
        this.allFiles = allFiles;
        this.sharedFiles = sharedFiles;
        this.root = root;
        this.repositoryName = repositoryName;
    }

    public async Task<SemanticAnalysisResult> RunAsync(
        StreamWriter occurrenceWriter,
        StreamWriter chainWriter)
    {
        Console.WriteLine();

        Console.WriteLine(
            "========== PHASE 2: SEMANTIC ANALYSIS ==========");

        var processedFiles =
            new HashSet<string>(
                StringComparer.OrdinalIgnoreCase);

        var occurrences =
            new List<LinqOccurrence>();

        var chains =
            new List<LinqChain>();

        int chainCount = 0;

        foreach (var project in loadedProjects.Values)
        {
            string projectName =
                Path.GetFileNameWithoutExtension(
                    project.Name);

            Console.WriteLine();

            Console.WriteLine(
                $"Project: {projectName}");

            var compilation =
                await project.GetCompilationAsync();

            if (compilation == null)
            {
                Console.WriteLine(
                    "ERROR: Could not obtain compilation.");

                continue;
            }

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

                if (!allFiles.Contains(filePath))
                {
                    Console.WriteLine(
                        $"WARNING: Analysis file was not discovered in Phase 1: {filePath}");
                }

                bool isShared =
                    sharedFiles.Contains(filePath);

                string csvProjectName =
                    isShared
                        ? projectName + "*"
                        : projectName;

                try
                {
                    var tree =
                        await document.GetSyntaxTreeAsync();

                    if (tree == null)
                        continue;

                    var rootNode =
                        await document.GetSyntaxRootAsync();

                    if (rootNode == null)
                        continue;

                    // Analyze each physical source file only once.
                    if (!processedFiles.Add(filePath))
                        continue;

                    var model =
                        compilation.GetSemanticModel(tree);

                    // ------------------------------------------------
                    // Report compilation errors, if any.
                    // ------------------------------------------------

                    var diagnostics =
                        model.GetDiagnostics();

                    foreach (var diagnostic in diagnostics)
                    {
                        if (diagnostic.Severity ==
                            DiagnosticSeverity.Error)
                        {
                            Console.WriteLine(
                                $"COMPILE ERROR: {diagnostic}");
                        }
                    }

                    // ------------------------------------------------
                    // Method-call LINQ occurrences
                    // ------------------------------------------------

                    var invocations =
                        rootNode.DescendantNodes()
                            .OfType<InvocationExpressionSyntax>();

                    foreach (var invocation in invocations)
                    {
                        var symbolInfo =
                            model.GetSymbolInfo(invocation);

                        if (symbolInfo.Symbol
                            is not IMethodSymbol methodSymbol)
                        {
                            continue;
                        }

                        string? containingType =
                            methodSymbol.ContainingType?
                                .ToDisplayString();

                        var lineSpan =
                            tree.GetLineSpan(
                                invocation.Span);

                        bool isLinq =
                            (
                                containingType ==
                                "System.Linq.Enumerable"
                                ||
                                containingType ==
                                "System.Linq.Queryable"
                            )
                            &&
                            methodSymbol.DeclaredAccessibility ==
                            Accessibility.Public;

                        if (!isLinq)
                            continue;

                        int line =
                            lineSpan.StartLinePosition.Line + 1;

                        string api =
                            containingType ==
                            "System.Linq.Enumerable"
                                ? "Enumerable"
                                : "Queryable";

                        occurrences.Add(
                            new LinqOccurrence(
                                Kind: LinqKind.MethodCall,
                                Operator: methodSymbol.Name,
                                Api: api,
                                File: filePath,
                                Line: line));

                        WriteOccurrenceLine(
                            occurrenceWriter,
                            repositoryName,
                            csvProjectName,
                            filePath,
                            line.ToString(),
                            LinqKind.MethodCall.ToString(),
                            methodSymbol.Name,
                            api);
                    }

                    // ------------------------------------------------
                    // LINQ query syntax
                    // ------------------------------------------------

                    Console.WriteLine(
                        $"QUERY ANALYSIS: {filePath} " +
                        $"Project={csvProjectName}");

                    AnalyzeQuerySyntax(
                        tree,
                        occurrences,
                        occurrenceWriter,
                        repositoryName,
                        csvProjectName);

                    var fileChains =
                        ChainDetection.FindChains(
                            rootNode,
                            model,
                            filePath);

                    chains.AddRange(fileChains);
                    chainCount += fileChains.Count;

                    foreach (var chain in fileChains)
                    {
                        WriteChainLine(
                            chainWriter,
                            repositoryName,
                            csvProjectName,
                            chain);
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine(
                        $"ERROR: {document.FilePath}");

                    Console.WriteLine(
                        $"  {ex.Message}");
                }
            }
        }

        return new SemanticAnalysisResult(
            processedFiles,
            occurrences,
            chains,
            chainCount);
    }

    private static void AnalyzeQuerySyntax(
        SyntaxTree tree,
        List<LinqOccurrence> occurrences,
        StreamWriter occurrenceWriter,
        string repository,
        string projectName)
    {
        var root =
            tree.GetRoot();

        foreach (
            var query in
            root.DescendantNodes()
                .OfType<QueryExpressionSyntax>())
        {
            foreach (var node in query.DescendantNodes())
            {
                string? op =
                    node switch
                    {
                        FromClauseSyntax => "From",
                        WhereClauseSyntax => "Where",
                        LetClauseSyntax => "Let",
                        JoinClauseSyntax => "Join",
                        OrderByClauseSyntax => "OrderBy",
                        SelectClauseSyntax => "Select",
                        GroupClauseSyntax => "GroupBy",
                        _ => null
                    };

                if (op == null)
                    continue;

                var lineSpan =
                    tree.GetLineSpan(
                        node.Span);

                int line =
                    lineSpan.StartLinePosition.Line + 1;

                string filePath =
                    tree.FilePath ?? "";

                occurrences.Add(
                    new LinqOccurrence(
                        Kind: LinqKind.QuerySyntax,
                        Operator: op,
                        Api: null,
                        File: filePath,
                        Line: line));

                WriteOccurrenceLine(
                    occurrenceWriter,
                    repository,
                    projectName,
                    filePath,
                    line.ToString(),
                    LinqKind.QuerySyntax.ToString(),
                    op,
                    "");
            }
        }
    }

    private static void WriteOccurrenceLine(
        StreamWriter occWriter,
        string repository,
        string projectName,
        string filePath,
        string line,
        string kind,
        string oper,
        string api)
    {
        occWriter.WriteLine(
            string.Join(
                ",",
                CsvUtilities.CsvField(repository),
                CsvUtilities.CsvField(projectName),
                CsvUtilities.CsvField(oper),
                CsvUtilities.CsvField(api),
                CsvUtilities.CsvField(kind),
                CsvUtilities.CsvField(filePath),
                CsvUtilities.CsvField(line)));
    }

    private static void WriteChainLine(
        StreamWriter writer,
        string repository,
        string projectName,
        LinqChain chain)
    {
        writer.WriteLine(
            string.Join(
                ",",
                CsvUtilities.CsvField(chain.ChainId),
                CsvUtilities.CsvField(repository),
                CsvUtilities.CsvField(projectName),
                CsvUtilities.CsvField(
                    $"{chain.LeftmostPosition.Line}," +
                    $"{chain.LeftmostPosition.Index}"),
                CsvUtilities.CsvField(
                    $"{chain.RightmostPosition.Line}," +
                    $"{chain.RightmostPosition.Index}"),
                CsvUtilities.CsvField(
                    string.Join(
                        " -> ",
                        chain.Methods))));
    }
}