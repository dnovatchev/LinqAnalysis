record SourcePosition(
    int Line,
    int Index);

record LinqChain(
    string ChainId,
    SourcePosition LeftmostPosition,
    SourcePosition RightmostPosition,
    IReadOnlyList<string> Methods);

