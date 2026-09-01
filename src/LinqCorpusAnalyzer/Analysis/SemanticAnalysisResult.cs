using System.Collections.Generic;

namespace LinqCorpusAnalyzerRefactored.Analysis;

internal sealed record SemanticAnalysisResult(
    IReadOnlySet<string> ProcessedFiles,
    IReadOnlyList<LinqOccurrence> Occurrences,
    IReadOnlyList<LinqChain> Chains,
    int ChainCount);