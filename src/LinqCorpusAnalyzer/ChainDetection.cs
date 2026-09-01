using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp.Syntax;

static class ChainDetection
{
    public static List<LinqChain> FindChains(
        SyntaxNode root,
        SemanticModel model,
        string filePath)
    {
        var chains =
            new List<LinqChain>();

        var invocations =
            root.DescendantNodes()
                .OfType<InvocationExpressionSyntax>()
                .ToList();

        foreach (var invocation in invocations)
        {
            var method =
                GetLinqMethod(
                    invocation,
                    model);

            if (method == null)
                continue;

            // This invocation starts a chain only if there is
            // no preceding LINQ invocation.
            if (GetPreviousLinqInvocation(
                    invocation,
                    model) != null)
            {
                continue;
            }

            var chainInvocations =
                new List<
                    (InvocationExpressionSyntax Invocation,
                     IMethodSymbol Method)>();

            var current =
                invocation;

            while (true)
            {
                var currentMethod =
                    GetLinqMethod(
                        current,
                        model);

                if (currentMethod == null)
                    break;

                chainInvocations.Add(
                    (current, currentMethod));

                var next =
                    GetNextInvocation(current);

                if (next == null ||
                    GetLinqMethod(next, model) == null)
                {
                    break;
                }

                current = next;
            }

            // We are interested in actual chains, not
            // isolated LINQ calls.
            if (chainInvocations.Count < 2)
                continue;

            var first =
                chainInvocations[0].Invocation;

            var last =
                chainInvocations[^1].Invocation;

            var leftmostPosition =
                GetMethodPosition(first);

            var rightmostPosition =
                GetEndPosition(
                    last.GetLocation());

            var methods =
                chainInvocations
                    .Select(
                        x =>
                            GetMethodName(
                                x.Method))
                    .ToList();

            string chainId =
                CreateChainId(
                    filePath,
                    leftmostPosition);

            chains.Add(
                new LinqChain(
                    chainId,
                    leftmostPosition,
                    rightmostPosition,
                    methods));
        }

        return chains;
    }

    private static IMethodSymbol? GetLinqMethod(
        InvocationExpressionSyntax invocation,
        SemanticModel model)
    {
        var symbolInfo =
            model.GetSymbolInfo(invocation);

        if (symbolInfo.Symbol
            is not IMethodSymbol method)
        {
            return null;
        }

        string? containingType =
            method.ContainingType?
                .ToDisplayString();

        if (containingType !=
                "System.Linq.Enumerable" &&
            containingType !=
                "System.Linq.Queryable")
        {
            return null;
        }

        if (method.DeclaredAccessibility !=
            Accessibility.Public)
        {
            return null;
        }

        return method;
    }

    private static ExpressionSyntax? GetReceiver(
        InvocationExpressionSyntax invocation)
    {
        if (invocation.Expression
            is MemberAccessExpressionSyntax memberAccess)
        {
            return memberAccess.Expression;
        }

        return null;
    }

    private static InvocationExpressionSyntax?
    GetPreviousLinqInvocation(
        InvocationExpressionSyntax invocation,
        SemanticModel model)
    {
        if (invocation.Expression
            is not MemberAccessExpressionSyntax memberAccess)
        {
            return null;
        }

        if (memberAccess.Expression
            is not InvocationExpressionSyntax previousInvocation)
        {
            return null;
        }

        return GetLinqMethod(
            previousInvocation,
            model) != null
                ? previousInvocation
                : null;
    }

    private static InvocationExpressionSyntax?
    GetNextInvocation(
        InvocationExpressionSyntax invocation)
    {
        if (invocation.Parent
            is not MemberAccessExpressionSyntax memberAccess)
        {
            return null;
        }

        if (memberAccess.Parent
            is not InvocationExpressionSyntax nextInvocation)
        {
            return null;
        }

        if (!ReferenceEquals(
                nextInvocation.Expression,
                memberAccess))
        {
            return null;
        }

        return nextInvocation;
    }

    private static string GetMethodName(
        IMethodSymbol method)
    {
        string prefix =
            method.ContainingType?
                .ToDisplayString() switch
            {
                "System.Linq.Enumerable" =>
                    "En_",

                "System.Linq.Queryable" =>
                    "Qu_",

                _ =>
                    throw new InvalidOperationException()
            };

        return prefix + method.Name;
    }

    private static SourcePosition GetMethodPosition(
    InvocationExpressionSyntax invocation)
    {
        if (invocation.Expression
            is MemberAccessExpressionSyntax memberAccess)
        {
            return GetPosition(
                memberAccess.Name.GetLocation());
        }

        return GetPosition(
            invocation.GetLocation());
    }

    private static SourcePosition GetPosition(
        Location location)
    {
        var lineSpan =
            location.GetLineSpan();

        var position =
            lineSpan.StartLinePosition;

        return new SourcePosition(
            position.Line + 1,
            position.Character);
    }

    private static string CreateChainId(
        string filePath,
        SourcePosition leftmostPosition)
    {
        return
            $"{filePath}:" +
            $"{leftmostPosition.Line}:" +
            $"{leftmostPosition.Index}";
    }

    private static SourcePosition GetEndPosition(Location location)
    {
        var lineSpan =
            location.GetLineSpan();

        var position =
            lineSpan.EndLinePosition;

        return new SourcePosition(
            position.Line + 1,
            position.Character);
    }
}