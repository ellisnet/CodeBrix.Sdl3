// Copyright (c) ppy Pty Ltd <contact@ppy.sh>. Licensed under the MIT Licence.
// See the LICENCE file in the repository root for full licence text.

using System.Collections.Generic;
using CodeBrix.Sdl3.Tests.Internal;
using SilverAssertions;
using Xunit;

namespace CodeBrix.Sdl3.Tests; //was previously: SDL.Tests;

public class SDLBoolTests
{
    [Fact]
    public void false_is_returned_as_false()
    {
        //Arrange
        Assert.SkipUnless(Sdl3NativeLibrary.IsAvailable, Sdl3NativeLibrary.SkipReason);

        //Act
        bool result = SDL3.SDL_OutOfMemory();

        //Assert
        result.Should().BeFalse();
    }

    [Fact]
    public void true_is_returned_as_true()
    {
        //Arrange
        Assert.SkipUnless(Sdl3NativeLibrary.IsAvailable, Sdl3NativeLibrary.SkipReason);

        //Act
        bool result = SDL3.SDL_ClearError();

        //Assert
        result.Should().BeTrue();
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void stored_property_value_round_trips(bool value)
    {
        //Arrange
        Assert.SkipUnless(Sdl3NativeLibrary.IsAvailable, Sdl3NativeLibrary.SkipReason);
        var props = SDL3.SDL_CreateProperties();
        Assert.SkipWhen(props == 0, "SDL_CreateProperties failed");

        try
        {
            bool stored = SDL3.SDL_SetBooleanProperty(props, "test", value);
            Assert.SkipUnless(stored, "SDL_SetBooleanProperty failed");

            //Act
            bool loaded = SDL3.SDL_GetBooleanProperty(props, "test", !value);

            //Assert
            loaded.Should().Be(value);
        }
        finally
        {
            SDL3.SDL_DestroyProperties(props);
        }
    }

    public static IEnumerable<TheoryDataRow<SDLBool, SDLBool>> BoolCases()
    {
        SDLBool[] values = [new SDLBool(4), true, false];

        foreach (var x in values)
        {
            foreach (var y in values)
            {
                yield return new TheoryDataRow<SDLBool, SDLBool>(x, y);
            }
        }
    }

    [Theory]
    [MemberData(nameof(BoolCases))]
    public void Equals_compares_truthiness(SDLBool first, SDLBool second)
    {
        //Assert
        ((SDLBool)(bool)first).Should().Be(first);
        first.Equals(second).Should().Be((bool)first == (bool)second);
        (first == second).Should().Be((bool)first == (bool)second);
    }
}
