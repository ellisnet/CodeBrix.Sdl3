// Copyright (c) ppy Pty Ltd <contact@ppy.sh>. Licensed under the MIT Licence.
// See the LICENCE file in the repository root for full licence text.

using System;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using SilverAssertions;
using Xunit;

namespace CodeBrix.Sdl3.Tests; //was previously: SDL.Tests;

public class Utf8StringTests
{
    [Fact]
    public void no_implicit_conversion_from_null_or_default()
    {
        //Assert
        checkNull(null);
        checkNull(default);
        checkNull(new Utf8String()); // don't do this in actual code
    }

    [Theory]
    [InlineData(null, -1)]
    [InlineData("", 1)]
    [InlineData("\0", 1)]
    [InlineData("test", 5)]
    [InlineData("test\0", 5)]
    [InlineData("test\0test", 10)]
    [InlineData("test\0test\0", 10)]
    public void string_conversion_is_null_terminated(string str, int expectedLength)
    {
        //Assert
        if (str == null)
            checkNull(str);
        else
            check(str, expectedLength);
    }

    [Fact]
    public void null_span_converts_to_null()
    {
        //Arrange
        ReadOnlySpan<byte> span = null;

        //Assert
        checkNull(span);
    }

    [Fact]
    public void default_span_converts_to_null()
    {
        //Arrange
        ReadOnlySpan<byte> span = default;

        //Assert
        checkNull(span);
    }

    [Fact]
    public void new_span_converts_to_null()
    {
        //Arrange
        ReadOnlySpan<byte> span = new ReadOnlySpan<byte>();

        //Assert
        checkNull(span);
    }

    [Fact]
    public void read_only_span_conversion_is_null_terminated()
    {
        //Assert
        check(""u8, 1);
        check("\0"u8, 1);
        check("test"u8, 5);
        check("test\0"u8, 5);
        check("test\0test"u8, 10);
        check("test\0test\0"u8, 10);
    }

    private static unsafe void checkNull(Utf8String s)
    {
        // upstream: s.Raw == null (CA2265) - the same test, a span whose reference is null
        Unsafe.IsNullRef(ref MemoryMarshal.GetReference(s.Raw)).Should().BeTrue("s.Raw == null");
        s.Raw.Length.Should().Be(0);

        fixed (byte* ptr = s)
        {
            (ptr == null).Should().BeTrue("ptr == null");
        }
    }

    private static unsafe void check(Utf8String s, int expectedLength)
    {
        s.Raw.Length.Should().Be(expectedLength);

        fixed (byte* ptr = s)
        {
            (ptr != null).Should().BeTrue("ptr != null");
            ptr[s.Raw.Length - 1].Should().Be(0);
        }
    }
}
