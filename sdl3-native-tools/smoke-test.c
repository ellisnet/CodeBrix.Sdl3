/*
 * smoke-test.c - the load-and-run verification program for the SDL3 native library
 *
 * Part of CodeBrix.Sdl3's sdl3-native-tools. One file, NO SDL headers, no build system: every
 * platform's gate compiles it with the plain C compiler and runs it against the STAGED (stripped,
 * about-to-be-shipped) library, so the bytes that are tested are the bytes that ship.
 *
 *     Linux / Android :  cc -std=c11 -O1 -o smoke-test smoke-test.c -ldl
 *     macOS           :  cc -std=c11 -O1 -o smoke-test smoke-test.c
 *     Windows (MSVC)  :  cl /nologo /O1 smoke-test.c
 *
 *     ./smoke-test <path-to-library> [expected-version-number]
 *
 * It loads the library the way .NET's DllImport does (dlopen / LoadLibrary, by path), resolves
 * the entry points it needs by name, and then:
 *   1. SDL_GetVersion() must equal the expected number (default 3005000 = SDL 3.5.0),
 *   2. prints SDL_GetRevision() and every compiled-in video and audio driver (which is the
 *      run-time confirmation of the backends the build enabled),
 *   3. SDL_SetHint(SDL_VIDEO_DRIVER, "dummy"), SDL_Init(SDL_INIT_VIDEO),
 *   4. creates a hidden 64x48 window and a renderer for it,
 *   5. clears to a known colour, reads one pixel back and checks it,
 *   6. destroys renderer and window, SDL_Quit().
 * The dummy video driver needs no display, GPU or windowing system, so this runs in a headless
 * build container (and under qemu-user emulation) exactly as on a desktop.
 *
 * Exit code 0 means every step passed; anything else names the step that failed.
 *
 * Function types are declared by hand from the SDL 3.5.0 headers (SDL_init.h, SDL_hints.h,
 * SDL_video.h, SDL_render.h, SDL_surface.h, SDL_version.h, SDL_audio.h). SDL's API uses C99
 * `bool` (one byte) for success/failure, Uint32 for SDL_InitFlags and Uint64 for
 * SDL_WindowFlags; SDLCALL is __cdecl on Windows and nothing elsewhere.
 */

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#if defined(_WIN32)
#  include <windows.h>
#  define SDLCALL __cdecl
typedef HMODULE lib_handle;
static lib_handle lib_open(const char *path) { return LoadLibraryA(path); }
static void *lib_sym(lib_handle h, const char *name) { return (void *)GetProcAddress(h, name); }
static const char *lib_error(void) { static char buf[64]; snprintf(buf, sizeof buf, "Win32 error %lu", (unsigned long)GetLastError()); return buf; }
#else
#  include <dlfcn.h>
#  define SDLCALL
typedef void *lib_handle;
static lib_handle lib_open(const char *path) { return dlopen(path, RTLD_NOW | RTLD_LOCAL); }
static void *lib_sym(lib_handle h, const char *name) { return dlsym(h, name); }
static const char *lib_error(void) { const char *e = dlerror(); return e ? e : "unknown"; }
#endif

#define SDL_INIT_VIDEO      0x00000020u
#define SDL_WINDOW_HIDDEN   UINT64_C(0x0000000000000008)

typedef int          (SDLCALL *fn_GetVersion)(void);
typedef const char * (SDLCALL *fn_GetRevision)(void);
typedef const char * (SDLCALL *fn_GetError)(void);
typedef bool         (SDLCALL *fn_SetHint)(const char *, const char *);
typedef bool         (SDLCALL *fn_Init)(uint32_t);
typedef void         (SDLCALL *fn_Quit)(void);
typedef int          (SDLCALL *fn_GetNumDrivers)(void);
typedef const char * (SDLCALL *fn_GetDriver)(int);
typedef const char * (SDLCALL *fn_GetCurrentVideoDriver)(void);
typedef void *       (SDLCALL *fn_CreateWindow)(const char *, int, int, uint64_t);
typedef void         (SDLCALL *fn_DestroyWindow)(void *);
typedef void *       (SDLCALL *fn_CreateRenderer)(void *, const char *);
typedef void         (SDLCALL *fn_DestroyRenderer)(void *);
typedef const char * (SDLCALL *fn_GetRendererName)(void *);
typedef bool         (SDLCALL *fn_SetRenderDrawColor)(void *, uint8_t, uint8_t, uint8_t, uint8_t);
typedef bool         (SDLCALL *fn_RenderClear)(void *);
typedef void *       (SDLCALL *fn_RenderReadPixels)(void *, const void *);
typedef bool         (SDLCALL *fn_RenderPresent)(void *);
typedef bool         (SDLCALL *fn_ReadSurfacePixel)(void *, int, int, uint8_t *, uint8_t *, uint8_t *, uint8_t *);
typedef void         (SDLCALL *fn_DestroySurface)(void *);

static lib_handle lib;
static int resolved = 0;

static void *need(const char *name)
{
    void *p = lib_sym(lib, name);
    if (!p) {
        fprintf(stderr, "FAIL: entry point %s is not exported\n", name);
        exit(10);
    }
    resolved++;
    return p;
}

#define FAIL(code, ...) do { fprintf(stderr, "FAIL: " __VA_ARGS__); fprintf(stderr, " (SDL_GetError: %s)\n", GetError()); return (code); } while (0)

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "usage: %s <path-to-SDL3-library> [expected-version-number]\n", argv[0]);
        return 2;
    }
    const char *path = argv[1];
    const int expected = argc > 2 ? atoi(argv[2]) : 3005000;

    lib = lib_open(path);
    if (!lib) {
        fprintf(stderr, "FAIL: could not load %s: %s\n", path, lib_error());
        return 3;
    }
    printf("loaded           : %s\n", path);

    fn_GetVersion            GetVersion            = (fn_GetVersion)need("SDL_GetVersion");
    fn_GetRevision           GetRevision           = (fn_GetRevision)need("SDL_GetRevision");
    fn_GetError              GetError              = (fn_GetError)need("SDL_GetError");
    fn_SetHint               SetHint               = (fn_SetHint)need("SDL_SetHint");
    fn_Init                  Init                  = (fn_Init)need("SDL_Init");
    fn_Quit                  Quit                  = (fn_Quit)need("SDL_Quit");
    fn_GetNumDrivers         GetNumVideoDrivers    = (fn_GetNumDrivers)need("SDL_GetNumVideoDrivers");
    fn_GetDriver             GetVideoDriver        = (fn_GetDriver)need("SDL_GetVideoDriver");
    fn_GetNumDrivers         GetNumAudioDrivers    = (fn_GetNumDrivers)need("SDL_GetNumAudioDrivers");
    fn_GetDriver             GetAudioDriver        = (fn_GetDriver)need("SDL_GetAudioDriver");
    fn_GetNumDrivers         GetNumRenderDrivers   = (fn_GetNumDrivers)need("SDL_GetNumRenderDrivers");
    fn_GetDriver             GetRenderDriver       = (fn_GetDriver)need("SDL_GetRenderDriver");
    fn_GetCurrentVideoDriver GetCurrentVideoDriver = (fn_GetCurrentVideoDriver)need("SDL_GetCurrentVideoDriver");
    fn_CreateWindow          CreateWindow_         = (fn_CreateWindow)need("SDL_CreateWindow");
    fn_DestroyWindow         DestroyWindow_        = (fn_DestroyWindow)need("SDL_DestroyWindow");
    fn_CreateRenderer        CreateRenderer        = (fn_CreateRenderer)need("SDL_CreateRenderer");
    fn_DestroyRenderer       DestroyRenderer       = (fn_DestroyRenderer)need("SDL_DestroyRenderer");
    fn_GetRendererName       GetRendererName       = (fn_GetRendererName)need("SDL_GetRendererName");
    fn_SetRenderDrawColor    SetRenderDrawColor    = (fn_SetRenderDrawColor)need("SDL_SetRenderDrawColor");
    fn_RenderClear           RenderClear           = (fn_RenderClear)need("SDL_RenderClear");
    fn_RenderReadPixels      RenderReadPixels      = (fn_RenderReadPixels)need("SDL_RenderReadPixels");
    fn_RenderPresent         RenderPresent         = (fn_RenderPresent)need("SDL_RenderPresent");
    fn_ReadSurfacePixel      ReadSurfacePixel      = (fn_ReadSurfacePixel)need("SDL_ReadSurfacePixel");
    fn_DestroySurface        DestroySurface        = (fn_DestroySurface)need("SDL_DestroySurface");
    printf("entry points     : %d resolved\n", resolved);

    /* 1. Version. */
    const int version = GetVersion();
    printf("SDL_GetVersion   : %d (%d.%d.%d)\n", version, version / 1000000, (version / 1000) % 1000, version % 1000);
    if (version != expected) {
        fprintf(stderr, "FAIL: SDL_GetVersion returned %d, expected %d\n", version, expected);
        return 4;
    }
    printf("SDL_GetRevision  : %s\n", GetRevision());

    /* 2. What was compiled in. */
    printf("video drivers    :");
    for (int i = 0, n = GetNumVideoDrivers(); i < n; i++) printf(" %s", GetVideoDriver(i));
    printf("\naudio drivers    :");
    for (int i = 0, n = GetNumAudioDrivers(); i < n; i++) printf(" %s", GetAudioDriver(i));
    printf("\nrender drivers   :");
    for (int i = 0, n = GetNumRenderDrivers(); i < n; i++) printf(" %s", GetRenderDriver(i));
    printf("\n");

    /* 3. Init on the dummy video driver - no display needed. */
    if (!SetHint("SDL_VIDEO_DRIVER", "dummy")) FAIL(5, "SDL_SetHint(SDL_VIDEO_DRIVER, dummy) returned false");
    if (!Init(SDL_INIT_VIDEO)) FAIL(6, "SDL_Init(SDL_INIT_VIDEO) returned false");
    printf("SDL_Init(VIDEO)  : ok, current video driver %s\n", GetCurrentVideoDriver());

    /* 4. Window + renderer. */
    void *window = CreateWindow_("CodeBrix.Sdl3 smoke test", 64, 48, SDL_WINDOW_HIDDEN);
    if (!window) { Quit(); FAIL(7, "SDL_CreateWindow returned NULL"); }
    void *renderer = CreateRenderer(window, NULL);
    if (!renderer) { DestroyWindow_(window); Quit(); FAIL(8, "SDL_CreateRenderer returned NULL"); }
    printf("window + renderer: ok, renderer %s\n", GetRendererName(renderer));

    /* 5. Draw something and read it back. */
    uint8_t r = 0, g = 0, b = 0, a = 0;
    bool drew = SetRenderDrawColor(renderer, 0x12, 0x34, 0x56, 0xFF) && RenderClear(renderer);
    void *surface = drew ? RenderReadPixels(renderer, NULL) : NULL;
    bool read = surface && ReadSurfacePixel(surface, 10, 10, &r, &g, &b, &a);
    if (surface) DestroySurface(surface);
    if (!drew || !read || r != 0x12 || g != 0x34 || b != 0x56) {
        DestroyRenderer(renderer); DestroyWindow_(window); Quit();
        FAIL(9, "clear/read-back: drew=%d read=%d pixel=(%u,%u,%u,%u), expected (18,52,86)", drew, read, r, g, b, a);
    }
    RenderPresent(renderer);
    printf("draw + read-back : ok, pixel (10,10) = (%u,%u,%u)\n", r, g, b);

    /* 6. Tear down. */
    DestroyRenderer(renderer);
    DestroyWindow_(window);
    Quit();
    printf("teardown         : ok\n");
    printf("SMOKE TEST PASSED\n");
    return 0;
}
