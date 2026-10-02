// Copyright (c) ppy Pty Ltd <contact@ppy.sh>. Licensed under the MIT Licence.
// See the LICENCE file in the repository root for full licence text.

using System;
using System.Runtime.InteropServices;
using CodeBrix.Sdl3.Tests.Internal;
using SilverAssertions;
using Xunit;

namespace CodeBrix.Sdl3.Tests; //was previously: SDL.Tests;

public class SDLArrayTests
{
    private static unsafe T* CopyToSdl<T>(T[] array)
        where T : unmanaged
    {
        UIntPtr size = (UIntPtr)(Marshal.SizeOf<T>() * array.Length);
        IntPtr target = SDL3.SDL_malloc(size);

        fixed (T* source = array)
        {
            SDL3.SDL_memcpy(target, (IntPtr)source, size);
        }

        return (T*)target;
    }

    private static unsafe T** CopyToSdl<T>(T*[] array)
        where T : unmanaged
    {
        UIntPtr size = (UIntPtr)(sizeof(IntPtr) * array.Length);
        IntPtr target = SDL3.SDL_malloc(size);

        fixed (T** source = array)
        {
            SDL3.SDL_memcpy(target, (IntPtr)source, size);
        }

        return (T**)target;
    }

    [Fact]
    public unsafe void array_enumerator_yields_values_in_order()
    {
        //Arrange
        Assert.SkipUnless(Sdl3NativeLibrary.IsAvailable, Sdl3NativeLibrary.SkipReason);
        int[] values = [10, 20, 30, 40];
        int* sdlMemory = CopyToSdl(values);

        //Act
        using var array = new SDLArray<int>(sdlMemory, values.Length);
        int index = 0;

        //Assert
        foreach (int i in array)
        {
            i.Should().Be(values[index++]);
        }
    }

    [Fact]
    public unsafe void const_opaque_pointer_array_enumerator_yields_pointers_in_order()
    {
        //Arrange
        Assert.SkipUnless(Sdl3NativeLibrary.IsAvailable, Sdl3NativeLibrary.SkipReason);
        int a = 10, b = 20, c = 30, d = 40;
        int*[] values = [&a, &b, &c, &d];
        int** sdlMemory = null;

        // Const pointer arrays are not freed automatically. Since the
        // unit test owns the memory, this must be done at the end of the
        // test.

        try
        {
            //Act
            sdlMemory = CopyToSdl(values);

            var array = new SDLConstOpaquePointerArray<int>(sdlMemory, values.Length);
            int index = 0;

            //Assert
            foreach (int* i in array)
            {
                ((IntPtr)i).Should().Be((IntPtr)values[index++]);
            }
        }
        finally
        {
            if (sdlMemory != null)
                SDL3.SDL_free(sdlMemory);
        }
    }

    [Fact]
    public unsafe void opaque_pointer_array_enumerator_yields_pointers_in_order()
    {
        //Arrange
        Assert.SkipUnless(Sdl3NativeLibrary.IsAvailable, Sdl3NativeLibrary.SkipReason);
        int a = 10, b = 20, c = 30, d = 40;
        int*[] values = [&a, &b, &c, &d];
        int** sdlMemory = CopyToSdl(values);

        //Act
        using var array = new SDLOpaquePointerArray<int>(sdlMemory, values.Length);
        int index = 0;

        //Assert
        foreach (int* i in array)
        {
            ((IntPtr)i).Should().Be((IntPtr)values[index++]);
        }
    }

    [Fact]
    public unsafe void pointer_array_enumerator_dereferences_in_order()
    {
        //Arrange
        Assert.SkipUnless(Sdl3NativeLibrary.IsAvailable, Sdl3NativeLibrary.SkipReason);
        int a = 10, b = 20, c = 30, d = 40;
        int*[] values = [&a, &b, &c, &d];
        int** memory = CopyToSdl(values);

        //Act
        using var array = new SDLPointerArray<int>(memory, values.Length);
        int index = 0;

        //Assert
        foreach (int i in array)
        {
            i.Should().Be(*values[index++]);
        }
    }
}
