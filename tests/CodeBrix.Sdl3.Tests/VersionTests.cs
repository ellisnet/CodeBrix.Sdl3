using CodeBrix.Sdl3.Tests.Internal;
using SilverAssertions;
using Xunit;

namespace CodeBrix.Sdl3.Tests;

public class VersionTests
{
    [Fact]
    public void SDL_VERSION_matches_the_header_version_constants()
        => SDL3.SDL_VERSION.Should().Be(SDL3.SDL_VERSIONNUM(SDL3.SDL_MAJOR_VERSION, SDL3.SDL_MINOR_VERSION, SDL3.SDL_MICRO_VERSION));

    [Fact]
    public void SDL_GetVersion_equals_the_vendored_header_version()
    {
        //Arrange
        Assert.SkipUnless(Sdl3NativeLibrary.IsAvailable, Sdl3NativeLibrary.SkipReason);

        //Act
        int version = SDL3.SDL_GetVersion();

        //Assert
        SDL3.SDL_VERSIONNUM_MAJOR(version).Should().Be(SDL3.SDL_MAJOR_VERSION);
        SDL3.SDL_VERSIONNUM_MINOR(version).Should().Be(SDL3.SDL_MINOR_VERSION);
        SDL3.SDL_VERSIONNUM_MICRO(version).Should().Be(SDL3.SDL_MICRO_VERSION);
        version.Should().Be(SDL3.SDL_VERSION);
    }

    [Fact]
    public void SDL_GetRevision_is_not_empty()
    {
        //Arrange
        Assert.SkipUnless(Sdl3NativeLibrary.IsAvailable, Sdl3NativeLibrary.SkipReason);

        //Act
        string revision = SDL3.SDL_GetRevision();

        //Assert
        revision.Should().NotBeNullOrWhiteSpace();
    }
}
