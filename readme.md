#LinqAnalysis

This repository contains the source code, database definitions, SQL queries, and PowerShell scripts used for the empirical study of LINQ usage in C# described in:

**“What Is Really Being Used? An Empirical Study of LINQ Usage in C#”**

The study analyzes LINQ usage in three open-source C# repositories and compares textual identification of LINQ usage with semantic identification based on the C# compiler's semantic model. It also analyzes LINQ method-chains and the frequencies and continuations of LINQ API-method-call sequences.

##Repository structure

LinqAnalysis/
├── src/
│   ├── LinqCorpusAnalyzer/
│   │   ├── LinqCorpusAnalyzer.csproj
│   │   ├── Program.cs
│   │   └── Analysis/
│   │       └── ...
│   │
│   └── LinqCorpusTextAnalyzer/
│       ├── LinqCorpusTextAnalyzer.csproj
│       ├── Program.cs
│       └── Analysis/
│           ├── TextAnalyzer.cs
│           └── TextAnalysisRunner.cs
│
├── database/
│   ├── LinqCorpus-Schema.sql
│   ├── CreateView_vw_OperatorTrigramContinuations.sql
│   ├── CreateView_vw_OperatorTrigramFrequencies.sql
│   └── dbo.vw_OperatorBigramContinuations.sql
│
├── queries/
│   ├── Get_01_SemanticVsTextualOccurrences.sql
│   ├── ...
│   └── Materialize_OperatorTrigramFrequencies.sql
│
├── scripts/
│   ├── GetCorpus.ps1
│   ├── MeasureCorpus.ps1
│   ├── RunCorpusAnalysis.ps1
│   ├── CompareTextualToSemantic.ps1
│   └── ...
│
├── README.md
├── LICENSE
└── .gitignore

##Analyzers

###LinqCorpusAnalyzer

`src/LinqCorpusAnalyzer` performs semantic analysis of C# source code using Roslyn. It identifies calls to the LINQ APIs and records semantic LINQ API-method-calls, LINQ method-chains, and related project and corpus measurements.

###LinqCorpusTextAnalyzer

`src/LinqCorpusTextAnalyzer` performs textual analysis of C# source files. It identifies occurrences of LINQ method names in source text without relying on semantic binding.

The textual analyzer **must be run after the semantic analyzer**. It uses the list of C# files processed by the semantic analyzer and therefore analyzes **exactly the same C# files**. This ensures that the comparison between textual LINQ candidates and semantically identified LINQ API-method-calls is performed over the same set of source files.

The two analyzers thus support the study's comparison between textual LINQ candidates and semantically confirmed LINQ API-method-calls.

##Corpus

The empirical study uses three open-source C# repositories:

- `dotnet\efcore`
- `dotnet\runtime`
- `serilog\serilog`

The corpus itself is **not included in this repository**. The scripts in `scripts/` document and automate the corpus acquisition and measurement process.

The analyzed repositories and their revisions are recorded by the corpus-measurement process so that the precise source revisions used for the study can be identified.

##Database

The SQL Server database used by the analysis is `LinqCorpus`.

`database/LinqCorpus-Schema.sql` contains the database schema, tables, constraints, and database views used by the analysis.

The database contains the measured corpus information and the semantic, textual, and LINQ-chain results produced by the analyzers.

The standalone view-definition scripts in `database\` correspond to views used by the analysis.

##SQL queries

The `queries\` directory contains the SQL queries used to obtain and analyze the empirical results.

The queries cover:

- semantic versus textual LINQ occurrences;
- LINQ API-method-call frequencies;
- API-method usage across repositories;
- LINQ chain statistics;
- LINQ chain pairs and patterns;
- cross-corpus comparisons;
- frequency-rank analysis and regression;
- bigram and trigram frequencies and continuations.

`Materialize_OperatorTrigramFrequencies.sql` materializes trigram-frequency results used by subsequent analysis.

##Reproduction workflow

The principal workflow is:

1. Acquire the source repositories using GetCorpus.ps1.
2. Measure the acquired corpus using MeasureCorpus.ps1.
3. Build and run the semantic analyzer.
4. Run the textual analyzer.
5. Populate the SQL Server database with the resulting measurements and analysis data.
6. Execute the SQL queries in queries/ to reproduce the reported analyses.

The PowerShell scripts in `scripts\` contain the corresponding corpus, analysis, comparison, and database-population operations.

The exact commands and paths used during the original analysis are retained in the scripts. In particular, the scripts preserve the original corpus-root convention used by the study.

##Requirements

The analysis requires, as applicable:

- Windows
- Git
- PowerShell
- .NET SDK compatible with the analyzer projects
- SQL Server
- A local copy of the corpus repositories

The semantic analyzer uses the Roslyn APIs provided through its .NET project dependencies.

##Reproducibility

The repository is intended to provide the implementation and database/query material necessary to reproduce the computational part of the study.

The paper reports the corpus revisions, corpus measurements, semantic and textual LINQ measurements, LINQ method-chain measurements, and subsequent statistical analyses obtained from this workflow.

The corpus repositories themselves remain separate because of their size and independent version histories.

##Paper

The research paper associated with this repository is:

**Dimitre Novatchev. “What Is Really Being Used? An Empirical Study of LINQ Usage in C#.”**

The paper provides the motivation, methodology, empirical results, and interpretation of the analyses implemented in this repository.