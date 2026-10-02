// Copyright (c) ppy Pty Ltd <contact@ppy.sh>. Licensed under the MIT Licence.
// See the LICENCE file in the repository root for full licence text.

using System;
using CodeBrix.Sdl3.Tests.Internal;
using SilverAssertions;
using Xunit;

namespace CodeBrix.Sdl3.Tests; //was previously: SDL.Tests;

// CodeBrix: SDL_Unsupported and SDL_InvalidParamError call the C-variadic SDL_SetError through
// __arglist. .NET supports the varargs P/Invoke calling convention only on Windows; everywhere
// else the runtime throws InvalidProgramException at the call. The upstream assertions run on
// Windows; on other operating systems the tests pin that documented runtime behaviour instead.
public class ErrorMacroTests
{
    [Fact]
    public void SDL_Unsupported_sets_the_unsupported_error()
    {
        //Arrange
        Assert.SkipUnless(Sdl3NativeLibrary.IsAvailable, Sdl3NativeLibrary.SkipReason);

        if (!OperatingSystem.IsWindows())
        {
            //Act
            Action act = () => SDL3.SDL_Unsupported();

            //Assert
            act.Should().Throw<InvalidProgramException>();
            return;
        }

        //Act
        bool result = SDL3.SDL_Unsupported();

        //Assert
        result.Should().BeFalse();
        SDL3.SDL_GetError().Should().Be("That operation is not supported");
    }

    [Fact]
    public void SDL_InvalidParamError_sets_the_invalid_parameter_error()
    {
        //Arrange
        Assert.SkipUnless(Sdl3NativeLibrary.IsAvailable, Sdl3NativeLibrary.SkipReason);

        if (!OperatingSystem.IsWindows())
        {
            //Act
            Action act = () => SDL3.SDL_InvalidParamError("test");

            //Assert
            act.Should().Throw<InvalidProgramException>();
            return;
        }

        //Act
        bool result = SDL3.SDL_InvalidParamError("test");

        //Assert
        result.Should().BeFalse();
        SDL3.SDL_GetError().Should().Be("Parameter 'test' is invalid");
    }
}
