// Copyright (c) ppy Pty Ltd <contact@ppy.sh>. Licensed under the MIT Licence.
// See the LICENCE file in the repository root for full licence text.
// Changes for CodeBrix: no longer an ISyntaxReceiver. The selection logic of OnVisitSyntaxNode is
// unchanged but split into IsCandidate (the cheap syntactic name check, the SyntaxProvider
// predicate) and Find (the SyntaxProvider transform, returning one GeneratedMethod or null);
// grouping by file name moved to FriendlyOverloadGenerator.

using System;
using System.Linq;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;

namespace CodeBrix.Sdl3.SourceGeneration; //was previously: SDL.SourceGeneration;

public static class UnfriendlyMethodFinder
{
    private static readonly string[] sdlPrefixes = ["SDL_", "TTF_", "IMG_", "MIX_"];

    /// <summary>
    /// Checks whether the method is from any SDL library.
    /// It identifies those by checking the SDL prefix in the method name.
    /// </summary>
    private static bool IsMethodFromSDL(MethodDeclarationSyntax methodNode)
    {
        foreach (string prefix in sdlPrefixes)
        {
            if (methodNode.Identifier.ValueText.StartsWith(prefix, StringComparison.Ordinal))
                return true;
        }

        return false;
    }

    private static bool IsUnsafe(MethodDeclarationSyntax method)
        => method.Identifier.ValueText.StartsWith(Helper.UnsafePrefix, StringComparison.Ordinal);

    /// <summary>
    /// Syntax-only pre-filter: a method declaration whose name has an SDL prefix or <see cref="Helper.UnsafePrefix"/>.
    /// </summary>
    public static bool IsCandidate(SyntaxNode syntaxNode)
        => syntaxNode is MethodDeclarationSyntax method && (IsMethodFromSDL(method) || IsUnsafe(method));

    /// <summary>
    /// Returns the method with the changes its friendly overload needs, or <c>null</c> when it needs none.
    /// </summary>
    public static GeneratedMethod? Find(MethodDeclarationSyntax method)
    {
        bool isUnsafe = IsUnsafe(method);

        if (!IsMethodFromSDL(method) && !isUnsafe)
            return null;

        if (method.ParameterList.Parameters.Any(p => p.Identifier.IsKind(SyntaxKind.ArgListKeyword)))
            return null;

        var changes = Changes.None;

        // if the method is not marked unsafe, the `byte*` is not a string.
        if (method.ReturnType.IsBytePtr() && isUnsafe)
        {
            changes |= Changes.ChangeReturnTypeToString | Changes.TrimUnsafeFromName;

            if (!method.IsReturnTypeConstCharPtr())
                changes |= Changes.FreeReturnedPointer;
        }

        foreach (var parameter in method.ParameterList.Parameters)
        {
            if (parameter.IsTypeConstCharPtr())
                changes |= Changes.ChangeParamsToUtf8String;
        }

        return changes != Changes.None ? new GeneratedMethod(method, changes) : null;
    }
}
