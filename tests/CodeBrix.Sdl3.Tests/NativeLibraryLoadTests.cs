using System;
using System.IO;
using CodeBrix.Sdl3.Tests.Internal;
using SilverAssertions;
using Xunit;

namespace CodeBrix.Sdl3.Tests;

public class NativeLibraryLoadTests
{
    [Fact]
    public void native_library_loads_from_the_package_layout_for_the_current_rid()
    {
        //Arrange
        TestContext.Current.SendDiagnosticMessage($"Current RID: {Sdl3NativeLibrary.Rid}; expected native: {Sdl3NativeLibrary.ExpectedPath}");
        Assert.SkipUnless(Sdl3NativeLibrary.IsAvailable, Sdl3NativeLibrary.SkipReason);

        //Act
        int version = SDL3.SDL_GetVersion();

        //Assert
        version.Should().BeGreaterThan(0);
        Sdl3NativeLibrary.LoadedPath.Should().Be(Sdl3NativeLibrary.ExpectedPath);
        Path.GetFileName(Path.GetDirectoryName(Path.GetDirectoryName(Sdl3NativeLibrary.LoadedPath))).Should().Be(Sdl3NativeLibrary.Rid);
        TestContext.Current.SendDiagnosticMessage($"Loaded {Sdl3NativeLibrary.LoadedPath} (SDL {version})");
    }

    [Fact]
    public void license_file_travels_beside_the_native_library()
    {
        //Arrange
        Assert.SkipUnless(Sdl3NativeLibrary.IsAvailable, Sdl3NativeLibrary.SkipReason);
        string license = Path.Combine(Path.GetDirectoryName(Sdl3NativeLibrary.ExpectedPath), "LICENSE-SDL3.txt");

        //Act
        string text = File.ReadAllText(license);

        //Assert
        text.Should().Contain("Sam Lantinga");
    }

    [Fact]
    public void Rid_is_a_portable_runtime_identifier()
        => Sdl3NativeLibrary.Rid.Should().MatchRegex("^(win|osx|linux|android)-(x64|arm64|riscv64|x86|arm)$");
}
