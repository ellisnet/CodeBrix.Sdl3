using CodeBrix.Sdl3.Tests.Internal;
using SilverAssertions;
using Xunit;

namespace CodeBrix.Sdl3.Tests;

public class DummyVideoDriverSmoke
{
    [Fact]
    public unsafe void window_and_renderer_can_be_created_on_the_dummy_video_driver()
    {
        //Arrange
        Assert.SkipUnless(Sdl3NativeLibrary.IsAvailable, Sdl3NativeLibrary.SkipReason);
        ((bool)SDL3.SDL_SetHint(SDL3.SDL_HINT_VIDEO_DRIVER, "dummy")).Should().BeTrue();

        try
        {
            //Act
            bool initialized = SDL3.SDL_Init(SDL_InitFlags.SDL_INIT_VIDEO);
            string initError = SDL3.SDL_GetError();
            string driver = SDL3.SDL_GetCurrentVideoDriver();
            SDL_Window* window = SDL3.SDL_CreateWindow("CodeBrix.Sdl3 smoke", 320, 240, SDL_WindowFlags.SDL_WINDOW_HIDDEN);
            string windowError = SDL3.SDL_GetError();
            SDL_Renderer* renderer = window == null ? null : SDL3.SDL_CreateRenderer(window, (byte*)null);
            string rendererError = SDL3.SDL_GetError();
            string rendererName = renderer == null ? null : SDL3.SDL_GetRendererName(renderer);

            //Assert
            initialized.Should().BeTrue(initError);
            driver.Should().Be("dummy");
            (window != null).Should().BeTrue(windowError);
            (renderer != null).Should().BeTrue(rendererError);
            rendererName.Should().NotBeNullOrEmpty();
            TestContext.Current.SendDiagnosticMessage($"Renderer on the dummy driver: {rendererName}");

            SDL3.SDL_DestroyRenderer(renderer);
            SDL3.SDL_DestroyWindow(window);
        }
        finally
        {
            SDL3.SDL_Quit();
            SDL3.SDL_ResetHint(SDL3.SDL_HINT_VIDEO_DRIVER);
        }
    }

    [Fact]
    public unsafe void readme_event_loop_runs_until_a_quit_event()
    {
        //Arrange
        Assert.SkipUnless(Sdl3NativeLibrary.IsAvailable, Sdl3NativeLibrary.SkipReason);
        SDL3.SDL_SetHint(SDL3.SDL_HINT_VIDEO_DRIVER, "dummy");

        try
        {
            ((bool)SDL3.SDL_Init(SDL_InitFlags.SDL_INIT_VIDEO)).Should().BeTrue(SDL3.SDL_GetError());
            SDL_Window* window = SDL3.SDL_CreateWindow("Hello SDL3", 800, 600, SDL_WindowFlags.SDL_WINDOW_RESIZABLE);
            SDL_Renderer* renderer = SDL3.SDL_CreateRenderer(window, (byte*)null);
            SDL_Event quit = default;
            quit.type = (uint)SDL_EventType.SDL_EVENT_QUIT;
            ((bool)SDL3.SDL_PushEvent(&quit)).Should().BeTrue(SDL3.SDL_GetError());

            //Act
            bool running = true;
            int frames = 0;
            SDL_Event e;
            while (running && frames < 100)
            {
                while (SDL3.SDL_PollEvent(&e))
                {
                    if (e.Type == SDL_EventType.SDL_EVENT_QUIT)
                        running = false;
                }

                SDL3.SDL_SetRenderDrawColor(renderer, 30, 60, 120, 255);
                SDL3.SDL_RenderClear(renderer);
                SDL3.SDL_RenderPresent(renderer);
                frames++;
            }

            //Assert
            running.Should().BeFalse();
            frames.Should().Be(1);

            SDL3.SDL_DestroyRenderer(renderer);
            SDL3.SDL_DestroyWindow(window);
        }
        finally
        {
            SDL3.SDL_Quit();
            SDL3.SDL_ResetHint(SDL3.SDL_HINT_VIDEO_DRIVER);
        }
    }

    [Fact]
    public unsafe void gamepad_enumeration_returns_an_array_on_a_headless_host()
    {
        //Arrange
        Assert.SkipUnless(Sdl3NativeLibrary.IsAvailable, Sdl3NativeLibrary.SkipReason);

        try
        {
            ((bool)SDL3.SDL_Init(SDL_InitFlags.SDL_INIT_GAMEPAD)).Should().BeTrue(SDL3.SDL_GetError());

            //Act
            using var ids = SDL3.SDL_GetGamepads();

            //Assert
            ids.Should().NotBeNull(SDL3.SDL_GetError());
            foreach (SDL_JoystickID id in ids)
            {
                SDL_Gamepad* pad = SDL3.SDL_OpenGamepad(id);
                TestContext.Current.SendDiagnosticMessage($"Gamepad: {SDL3.SDL_GetGamepadName(pad)}");
                SDL3.SDL_CloseGamepad(pad);
            }
        }
        finally
        {
            SDL3.SDL_Quit();
        }
    }
}
