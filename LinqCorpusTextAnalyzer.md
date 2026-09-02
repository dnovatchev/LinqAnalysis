### LinqCorpusTextAnalyzer

`src/LinqCorpusTextAnalyzer` performs textual analysis of C# source files. It identifies occurrences of LINQ method names in source text without relying on semantic binding.

The textual analyzer **must be run after the semantic analyzer**. It uses the list of C# files processed by the semantic analyzer and therefore analyzes **exactly the same C# files**. This ensures that the comparison between textual LINQ candidates and semantically identified LINQ API-method-calls is performed over the same set of source files.

The two analyzers thus support the study's comparison between textual LINQ candidates and semantically confirmed LINQ API-method-calls.