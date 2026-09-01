namespace LinqCorpusAnalyzerRefactored.Utilities;

public static class CsvUtilities
{
    public static string CsvField(string value)
    {
        if (value.Contains('"') ||
            value.Contains(',') ||
            value.Contains('\r') ||
            value.Contains('\n'))
        {
            return "\"" +
                   value.Replace("\"", "\"\"") +
                   "\"";
        }

        return value;
    }
}