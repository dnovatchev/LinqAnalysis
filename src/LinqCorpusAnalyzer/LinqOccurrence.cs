public enum LinqKind
{
    MethodCall,
    QuerySyntax,
    ZeroOccurrence_EnumerableMethod,
    ZeroOccurrence_QueryableMethod
}

public record LinqOccurrence(
    LinqKind Kind,
    string Operator,
    string? Api,
    string File,
    int Line);

public record LinqApiHistoryEntry(
    string Generation,
    string Version,
    string TargetFramework,
    string Api,
    string Operator);

public record LinqHomonym(
    string Api,
    string Operator);
