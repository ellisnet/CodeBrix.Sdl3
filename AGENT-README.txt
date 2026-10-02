================================================================================
AGENT-README: CodeBrix.Sdl3
A Guide for AI Coding Agents - CONSUMING the
CodeBrix.Sdl3.ZlibLicenseForever NuGet package
================================================================================

OVERVIEW
========
CodeBrix.Sdl3 is a set of C# bindings for SDL3 (Simple DirectMedia Layer 3),
the cross-platform C library for windows, input, gamepads, audio, cameras, 2D
rendering, the SDL GPU API and the rest of the SDL3 API - together with the
SDL3 native library for nine runtime identifiers. It targets .NET 10 or later
(net10.0, plus net10.0-android for Android applications).

The bindings are a near one-to-one projection of the SDL3 C API: the same
function, struct, enum and constant names as the C headers, as static members
of one class (SDL3) plus top-level structs and enums. Almost all of it is
generated from the SDL3 headers; a thin hand-written layer adds C# conveniences
(string overloads, SDLBool, typed flag enums, array wrappers, the C macros as
methods).

Provenance: the bindings are a port of the ppy/SDL3-CS project (MIT), with the
namespace renamed from "SDL" to "CodeBrix.Sdl3". Do NOT write `using SDL;` -
that namespace does not exist in this package.


INSTALLATION
============
PackageId:  CodeBrix.Sdl3.ZlibLicenseForever

    dotnet add package CodeBrix.Sdl3.ZlibLicenseForever

IMPORTANT: the NuGet package id is CodeBrix.Sdl3.ZlibLicenseForever (NOT
"CodeBrix.Sdl3" - that suffix exists only to make the package license obvious
forever). The assembly and namespace are CodeBrix.Sdl3.

NuGet dependencies: none.

License: MIT AND Zlib (the managed bindings are MIT; SDL3 itself, the native
binaries and the code generated from its headers are zlib). The package
requires license acceptance.

Requirements:
  - .NET 10 or later.
  - <AllowUnsafeBlocks>true</AllowUnsafeBlocks> in the consuming project: the
    API is pointer-based (SDL_Window*, SDL_Renderer*, SDL_Event*, byte*).
  - One of the supported runtime identifiers (below).

NATIVE LIBRARIES - included, nothing to install. The package carries the SDL3
native library under runtimes/<rid>/native/ for:

    win-x64        SDL3.dll
    win-arm64      SDL3.dll
    osx-x64        libSDL3.dylib
    osx-arm64      libSDL3.dylib
    linux-x64      libSDL3.so
    linux-arm64    libSDL3.so
    linux-riscv64  libSDL3.so
    android-x64    libSDL3.so
    android-arm64  libSDL3.so

Each sits next to LICENSE-SDL3.txt. The .NET host picks the right one for the
running platform (a framework-dependent `dotnet run` uses the deps.json entry;
a RID-specific build or publish copies just that one file next to the app).
Every [DllImport] uses the library name "SDL3", which resolves to the files
above. The Linux libraries are built for an old glibc baseline and load SDL's
X11 / Wayland / ALSA / PulseAudio / PipeWire backends at run time from the
system, so a missing backend simply is not offered rather than failing to
load.

ANDROID: reference the package from a net10.0-android application. The
net10.0-android build of the assembly additionally carries the SDL Java bridge
(the org.libsdl.app classes, bound to C# in the Org.Libsdl.App namespace), and
the android natives arrive in the APK automatically. SDL on Android REQUIRES
that the application's activity is an SDLActivity - see "ANDROID" below.


KEY NAMESPACES / USINGS
=======================
    using CodeBrix.Sdl3;                   // structs, enums, SDLBool, Utf8String,
                                           // SDLArray<T> and friends
    using static CodeBrix.Sdl3.SDL3;       // every SDL_* function and constant
                                           // without the "SDL3." prefix

    using Org.Libsdl.App;                  // Android only: SDLActivity

There are no other public namespaces. (JetBrains.Annotations attributes in the
assembly are internal.)


CORE API REFERENCE
==================

THE SDL3 CLASS
--------------
`public static unsafe partial class SDL3` holds every SDL function, constant
and macro. Names are exactly the C names:

    SDL3.SDL_Init(SDL_InitFlags.SDL_INIT_VIDEO | SDL_InitFlags.SDL_INIT_GAMEPAD)
    SDL3.SDL_CreateWindow("title", 800, 600, SDL_WindowFlags.SDL_WINDOW_RESIZABLE)
    SDL3.SDL_GetError()
    SDL3.SDL_MAJOR_VERSION

With `using static CodeBrix.Sdl3.SDL3;` they read like C: SDL_Init(...).

Native functions are `[DllImport("SDL3")] static extern` declarations. Any
SDL documentation for the C function applies unchanged: the SDL3 wiki
(https://wiki.libsdl.org/SDL3/) is the reference for behaviour, ownership and
threading rules.

TYPE MAPPING
------------
    C                         C#
    bool                      SDLBool (implicitly converts to/from bool)
    char / Uint8              byte
    const char * (param)      byte*  AND a friendly overload taking Utf8String
    const char * (return)     string (friendly overload) - the raw byte*
                              variant is named Unsafe_<function>
    char * (return, caller    string (friendly overload; SDL_free is called
      must free)              for you)
    void *                    IntPtr
    Sint64 / Uint64           long / ulong
    size_t                    UIntPtr (nuint)
    opaque handles            SDL_Window*, SDL_Renderer*, SDL_Gamepad*, ...
    ID typedefs               small structs (SDL_JoystickID, SDL_DisplayID,
                              SDL_AudioDeviceID, SDL_PropertiesID, ...)
    #define flag sets         typed [Flags] enums (SDL_InitFlags,
                              SDL_WindowFlags, ...) AND the raw constants
    callbacks                 delegate* unmanaged[Cdecl]<...> function pointers

FRIENDLY OVERLOADS (generated at compile time)
----------------------------------------------
For every function with a `const char *` parameter there is an overload whose
parameter is `Utf8String`; a C# string or a UTF-8 literal converts implicitly:

    SDL_SetHint(SDL_HINT_VIDEO_DRIVER, "x11");     // string
    SDL_SetHint(SDL_HINT_VIDEO_DRIVER, "x11"u8);   // ReadOnlySpan<byte>
    SDL_SetAppMetadata("My App", "1.0", "com.example.myapp");

For every function returning `const char *` or `char *` the friendly overload
returns `string?` and the raw pointer version is `Unsafe_SDL_...`:

    string? err  = SDL_GetError();
    string? name = SDL_GetGamepadName(pad);
    byte*   raw  = Unsafe_SDL_GetError();              // rarely needed

SDL_HINT_* and similar string #defines are `ReadOnlySpan<byte>` UTF-8
properties, usable anywhere a Utf8String is expected.

Utf8String
----------
`public readonly ref struct Utf8String` - a null pointer or a NUL-terminated
UTF-8 buffer. Only ever create it through the implicit conversions from
`string` or `ReadOnlySpan<byte>` (a terminating NUL is appended if missing;
`null`/default converts to a null pointer). It is a ref struct: it cannot be
stored in a field, captured by a lambda or used across an await.

SDLBool
-------
`public readonly record struct SDLBool` - SDL's C `bool`. Converts implicitly
to and from `bool`, so `if (!SDL_Init(...))` works. Do not construct one
explicitly; any non-zero native value is true and equality compares truth.

ARRAY RESULTS
-------------
Functions that return an SDL-allocated array have an overload that wraps it:

    SDLArray<T>                       T*  owned by caller  - Dispose frees it
    SDLPointerArray<T>                T** owned by caller  - indexer
                                      dereferences
    SDLOpaquePointerArray<T>          T** of opaque handles - Dispose frees
    SDLConstOpaquePointerArray<T>     const T** owned by SDL - NOT disposable

Each has Count, an indexer and a foreach enumerator, and the overloads return
null when SDL returned NULL (check SDL_GetError()):

    using var pads = SDL_GetGamepads();
    if (pads != null)
        foreach (SDL_JoystickID id in pads) { ... }

Examples: SDL_GetGamepads, SDL_GetKeyboards, SDL_GetDisplays,
SDL_GetFullscreenDisplayModes, SDL_GetWindows, SDL_GetAudioPlaybackDevices,
SDL_GetAudioRecordingDevices, SDL_GetGamepadMappings.

STRINGS FROM POINTERS
---------------------
    string? SDL3.PtrToStringUTF8(byte* ptr, bool free = false)

Copies a NUL-terminated UTF-8 string; free: true also calls SDL_free(ptr).
Event structs carry helpers for their string members, e.g.
SDL_TextInputEvent.GetText(), SDL_DropEvent.GetData().

EVENTS
------
SDL_Event is a union struct. Read `e.Type` (SDL_EventType) and then the
matching member: e.key, e.button, e.motion, e.gbutton, e.gaxis, e.window,
e.text, e.drop, ... Typed helpers exist on several event structs
(SDL_MouseButtonEvent.Button, SDL_GamepadButtonEvent.Button,
SDL_GamepadAxisEvent.Axis).

MACROS
------
C macros are methods marked [Macro]: SDL_VERSIONNUM, SDL_VERSIONNUM_MAJOR/
MINOR/MICRO, SDL_WINDOWPOS_CENTERED_DISPLAY, SDL_AUDIO_BITSIZE,
SDL_DEFINE_PIXELFORMAT and so on.

ERROR MODEL
-----------
Nothing throws for an SDL failure. Functions report failure exactly as in C -
false (SDLBool), null pointer, 0 ID or -1 - and SDL_GetError() returns the
message. Check every return value that can fail.

ANDROID
-------
SDL on Android is driven by its Java activity. The application's main activity
must derive from Org.Libsdl.App.SDLActivity; override GetLibraries() to load
only "SDL3" and override Main() to run your C# entry point on SDL's thread:

    using Android.App;
    using Org.Libsdl.App;

    [Activity(Label = "My SDL App", MainLauncher = true)]
    public class MainActivity : SDLActivity
    {
        protected override string[] GetLibraries() => ["SDL3"];

        protected override void Main() => MyGame.Run();   // your SDL loop
    }

SDL_Init and the rest of the API are then used exactly as on the desktop,
from inside Main(). The android natives and the Java bridge come from the
package; the activity class is the only Android-specific code.


COMPLETE EXAMPLES
=================

1. Window + renderer + event loop
---------------------------------
    using System;
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

Passing `(byte*)null` as the renderer name lets SDL pick the best renderer;
the cast makes it obvious which of the two overloads (byte* or Utf8String) is
meant.

2. Headless use (CI, servers, tests): the dummy video driver
------------------------------------------------------------
    SDL_SetHint(SDL_HINT_VIDEO_DRIVER, "dummy");
    if (!SDL_Init(SDL_InitFlags.SDL_INIT_VIDEO))
        throw new InvalidOperationException(SDL_GetError());
    SDL_Window* w = SDL_CreateWindow("offscreen", 320, 240, SDL_WindowFlags.SDL_WINDOW_HIDDEN);
    SDL_Renderer* r = SDL_CreateRenderer(w, (byte*)null);   // "software"
    ...
    SDL_DestroyRenderer(r);
    SDL_DestroyWindow(w);
    SDL_Quit();

3. Gamepads
-----------
    SDL_Init(SDL_InitFlags.SDL_INIT_GAMEPAD);
    using (var ids = SDL_GetGamepads())
    {
        if (ids != null)
        {
            foreach (SDL_JoystickID id in ids)
            {
                SDL_Gamepad* pad = SDL_OpenGamepad(id);
                Console.WriteLine(SDL_GetGamepadName(pad));
            }
        }
    }
    // then handle SDL_EVENT_GAMEPAD_BUTTON_DOWN / _AXIS_MOTION in the event loop
    // via e.gbutton.Button and e.gaxis.Axis

4. Version information
----------------------
    int v = SDL_GetVersion();
    Console.WriteLine($"{SDL_VERSIONNUM_MAJOR(v)}.{SDL_VERSIONNUM_MINOR(v)}.{SDL_VERSIONNUM_MICRO(v)}");
    Console.WriteLine(SDL_GetRevision());
    // SDL_VERSION / SDL_MAJOR_VERSION ... are the header constants the bindings
    // were generated from; SDL_GetVersion() is the loaded library.


MINIMUM VIABLE PROJECT TEMPLATE
===============================
    <Project Sdk="Microsoft.NET.Sdk">
      <PropertyGroup>
        <OutputType>Exe</OutputType>
        <TargetFramework>net10.0</TargetFramework>
        <AllowUnsafeBlocks>true</AllowUnsafeBlocks>
      </PropertyGroup>
      <ItemGroup>
        <PackageReference Include="CodeBrix.Sdl3.ZlibLicenseForever" Version="*" />
      </ItemGroup>
    </Project>

(Pin the current version rather than "*" in real projects.) Program.cs is
example 1 above.


PERFORMANCE TIPS
================
  - Prefer the byte* / UTF-8 literal ("..."u8) forms in per-frame code: the
    string overloads allocate and encode on every call.
  - Poll events with a stack SDL_Event (`SDL_Event e; SDL_PollEvent(&e)`), not
    an array or a boxed copy.
  - Dispose SDLArray results promptly (using) - each holds SDL-allocated
    memory.
  - SDL functions are thread-affine where SDL says so (video and events on the
    main thread); follow the SDL wiki rather than adding locks.


COMMON PITFALLS TO AVOID
========================
  - `using SDL;` does not compile - the namespace is CodeBrix.Sdl3.
  - Forgetting <AllowUnsafeBlocks>true</AllowUnsafeBlocks>: CS0227 on the
    first pointer.
  - C-variadic functions (SDL_SetError, SDL_Log and the SDL_Log* family,
    SDL_snprintf, SDL_asprintf, SDL_sscanf, SDL_IOprintf,
    SDL_RenderDebugTextFormat, and the SDL_Unsupported / SDL_InvalidParamError
    macros) are declared with __arglist. .NET supports that calling convention
    only on Windows; on Linux, macOS and Android the call throws
    InvalidProgramException ("Vararg calling convention not supported").
    Format the text in C# and call a non-variadic function instead - e.g.
    SDL_RenderDebugText(renderer, x, y, $"...") rather than
    SDL_RenderDebugTextFormat - and log through your own logger rather than
    SDL_Log.
  - Calling SDL_free on strings returned by the friendly overloads: they are
    already copied (and freed where SDL required it). Only free what an
    Unsafe_ / byte* variant documents as caller-owned.
  - Storing a Utf8String: it is a ref struct and points at a temporary buffer.
    Convert at the call site.
  - Treating SDLBool as an int: compare with true/false or use it as bool.
  - Not checking returns: a null SDL_Window* or false from SDL_Init is a
    failure with a message in SDL_GetError(), never an exception.
  - Android: an activity that is not an SDLActivity (or that does not
    override GetLibraries to include "SDL3") leaves SDL uninitialized.
  - Running on a runtime identifier that is not listed above (win-x86,
    linux-x86, linux-arm, android-arm/x86, iOS): there is no native library
    for it and the first call throws DllNotFoundException.


WHAT THIS PACKAGE DOES NOT DO
=============================
  - No SDL_image, SDL_ttf, SDL_mixer or SDL_net bindings or natives - SDL3
    core only.
  - No iOS, win-x86, linux-x86, 32-bit ARM (linux-arm, android-arm) or
    android-x86 natives.
  - No higher-level object model (no Window class, no game loop) - it is the
    SDL3 API as SDL defines it.
  - No managed wrappers around variadic functions (see COMMON PITFALLS).


WORKING EXAMPLES ON GITHUB
==========================
  Tests: https://github.com/ellisnet/CodeBrix.Sdl3/tree/main/tests/CodeBrix.Sdl3.Tests

    DummyVideoDriverSmoke.cs     hint, init, window, renderer, event loop on
                                 the dummy video driver
    VersionTests.cs              SDL_GetVersion, SDL_GetRevision, version macros
    Utf8StringTests.cs           Utf8String conversions and NUL termination
    SDLArrayTests.cs             SDLArray / SDLPointerArray / opaque arrays
    SDLBoolTests.cs              SDLBool conversions and properties round trip
    ErrorMacroTests.cs           SDL_Unsupported / SDL_InvalidParamError and the
                                 variadic-call platform behaviour
    NativeLibraryLoadTests.cs    the runtimes/<rid>/native layout


QUICK REFERENCE CARD
====================
    Install         dotnet add package CodeBrix.Sdl3.ZlibLicenseForever
    Usings          using CodeBrix.Sdl3; using static CodeBrix.Sdl3.SDL3;
    Project         <AllowUnsafeBlocks>true</AllowUnsafeBlocks>
    Init / quit     SDL_Init(SDL_InitFlags.SDL_INIT_VIDEO) ... SDL_Quit()
    Window          SDL_CreateWindow(title, w, h, SDL_WindowFlags.X)
    Renderer        SDL_CreateRenderer(window, (byte*)null)
    Events          SDL_Event e; while (SDL_PollEvent(&e)) { e.Type ... }
    Errors          bool/null/0 return + SDL_GetError()
    Strings in      string or "..."u8 (Utf8String overloads)
    Strings out     string? (friendly) / Unsafe_SDL_X (byte*)
    Arrays          using var a = SDL_GetGamepads(); foreach (var id in a)
    Headless        SDL_SetHint(SDL_HINT_VIDEO_DRIVER, "dummy")
    Version         SDL_GetVersion(), SDL_GetRevision(), SDL_VERSION
    Android         MainActivity : Org.Libsdl.App.SDLActivity
    Variadics       Windows only - use the non-variadic alternative

Target: .NET 10 or later (net10.0, net10.0-android)
License: MIT AND Zlib


================================================================================
END OF AGENT-README
================================================================================
