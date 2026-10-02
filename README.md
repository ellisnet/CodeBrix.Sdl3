# CodeBrix.Sdl3

C# bindings for SDL3 (Simple DirectMedia Layer 3), with the SDL3 native libraries included, for .NET.
CodeBrix.Sdl3 is provided as a .NET 10 library and associated `CodeBrix.Sdl3.ZlibLicenseForever` NuGet package.

CodeBrix.Sdl3 supports applications and assemblies that target Microsoft .NET version 10.0 and later.
Microsoft .NET version 10.0 is a Long-Term Supported (LTS) version of .NET, and was released on Nov 11, 2025; and will be actively supported by Microsoft until Nov 14, 2028.
Please update your C#/.NET code and projects to the latest LTS version of Microsoft .NET.

## Installation

```
dotnet add package CodeBrix.Sdl3.ZlibLicenseForever
```

Note that the NuGet package ID and the namespace are different - there is no package named plain `CodeBrix.Sdl3`:

* NuGet package ID: `CodeBrix.Sdl3.ZlibLicenseForever`
* Assembly and primary namespace: `CodeBrix.Sdl3` - i.e. `using CodeBrix.Sdl3;`

XML documentation (IntelliSense) ships alongside the assembly.

CodeBrix.Sdl3 has no dependencies other than .NET. The SDL3 native library for each supported platform is inside the package.

## CodeBrix.Sdl3 supports:

* The SDL3 C API from C#, generated from the SDL3 headers: initialization, windows and displays, events, keyboard, mouse, pen, touch, gamepads and joysticks, haptics, sensors, audio, cameras, the 2D renderer, the GPU API, surfaces and pixel formats, clipboard, file dialogs, filesystem and storage, I/O streams, properties, threads, timers, logging, tray icons and more
* All SDL3 `#define` constants, enums, structs, callbacks and macros, as C# constants, enums, structs, function pointers and methods
* Friendly overloads that take C# strings for `const char *` parameters and return C# strings for `char *` results
* `SDLBool`, `Utf8String` and SDL-owned array helpers that free SDL memory when disposed
* Native libraries for nine runtime identifiers, selected automatically by NuGet: `win-x64`, `win-arm64`, `osx-x64`, `osx-arm64`, `linux-x64`, `linux-arm64`, `linux-riscv64`, `android-x64`, `android-arm64`
* A `net10.0-android` build that carries the SDL Java bridge (`SDLActivity`) for Android applications

## Native assets

The SDL3 native library is packed under `runtimes/<rid>/native/` for every runtime identifier listed above, next to a copy of the SDL3 licence. Nothing has to be installed on the target machine and no extra package is needed - building or publishing an application for a supported runtime identifier picks up the matching binary.

The Linux libraries are built for a low glibc baseline and load SDL's windowing, input and audio backends (X11, Wayland, ALSA, PulseAudio, PipeWire and so on) at run time from whatever the system provides, so the same binary runs on current desktop distributions.

## Sample Code

### Open a window and clear it every frame

```csharp
using CodeBrix.Sdl3;
using static CodeBrix.Sdl3.SDL3;

unsafe
{
    if (!SDL_Init(SDL_InitFlags.SDL_INIT_VIDEO))
        throw new InvalidOperationException($"SDL_Init failed: {SDL_GetError()}");

    SDL_Window* window = SDL_CreateWindow("Hello SDL3", 800, 600, SDL_WindowFlags.SDL_WINDOW_RESIZABLE);
    SDL_Renderer* renderer = SDL_CreateRenderer(window, (byte*)null);

    bool running = true;
    SDL_Event e;
    while (running)
    {
        while (SDL_PollEvent(&e))
        {
            if (e.Type == SDL_EventType.SDL_EVENT_QUIT)
                running = false;
        }

        SDL_SetRenderDrawColor(renderer, 30, 60, 120, 255);
        SDL_RenderClear(renderer);
        SDL_RenderPresent(renderer);
    }

    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();
}
```

The project needs `<AllowUnsafeBlocks>true</AllowUnsafeBlocks>` - the bindings are pointer-based.

### Read the SDL version

```csharp
using static CodeBrix.Sdl3.SDL3;

int version = SDL_GetVersion();
Console.WriteLine($"SDL {SDL_VERSIONNUM_MAJOR(version)}.{SDL_VERSIONNUM_MINOR(version)}.{SDL_VERSIONNUM_MICRO(version)} ({SDL_GetRevision()})");
```

## Documentation

The NuGet package includes `AGENT-README.txt`, a complete API reference and usage guide written for AI coding agents - point your agent at that file when it is writing code against this library.

Additional sample code and usage examples are available in the `CodeBrix.Sdl3.Tests` project:
https://github.com/ellisnet/CodeBrix.Sdl3/tree/main/tests/CodeBrix.Sdl3.Tests

## License

CodeBrix.Sdl3 is licensed under the MIT License - see the
[LICENSE](https://github.com/ellisnet/CodeBrix.Sdl3/blob/main/LICENSE) file.

For licensing and provenance information about the open source code included in
this package, see [THIRD-PARTY-NOTICES.txt](https://github.com/ellisnet/CodeBrix.Sdl3/blob/main/THIRD-PARTY-NOTICES.txt).
