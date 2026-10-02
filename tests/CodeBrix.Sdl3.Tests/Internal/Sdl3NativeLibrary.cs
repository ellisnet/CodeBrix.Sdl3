using System;
using System.IO;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using CodeBrix.Sdl3;

namespace CodeBrix.Sdl3.Tests.Internal;

/// <summary>
/// Locates the SDL3 native library for the current runtime identifier in the test output's
/// runtimes/&lt;rid&gt;/native/ folder (the package layout) and installs a DllImport resolver for the
/// CodeBrix.Sdl3 assembly that loads exactly that file.
/// </summary>
internal static class Sdl3NativeLibrary
{
    private static IntPtr _handle;

    /// <summary>The portable runtime identifier of the running process, e.g. linux-x64.</summary>
    public static string Rid { get; } = ComputeRid();

    /// <summary>The native file name the DllImport name "SDL3" maps to on this OS.</summary>
    public static string FileName { get; } =
        OperatingSystem.IsWindows() ? "SDL3.dll" : OperatingSystem.IsMacOS() ? "libSDL3.dylib" : "libSDL3.so";

    /// <summary>The full path the package layout puts the native library at for this process.</summary>
    public static string ExpectedPath { get; } = Path.Combine(AppContext.BaseDirectory, "runtimes", Rid, "native", FileName);

    /// <summary>Whether the native library for this RID is present in the test output.</summary>
    public static bool IsAvailable => File.Exists(ExpectedPath);

    /// <summary>The skip reason used by tests that need the native library.</summary>
    public static string SkipReason =>
        $"The SDL3 native library for {Rid} is not present at {ExpectedPath} - native_libraries/{Rid}/{FileName} has not been produced yet.";

    /// <summary>The path the resolver actually loaded, or null before the first native call.</summary>
    public static string LoadedPath { get; private set; }

    [ModuleInitializer]
    internal static void Install()
        => NativeLibrary.SetDllImportResolver(typeof(SDL3).Assembly, Resolve);

    private static IntPtr Resolve(string libraryName, Assembly assembly, DllImportSearchPath? searchPath)
    {
        if (libraryName != "SDL3" || !IsAvailable)
            return IntPtr.Zero;

        if (_handle == IntPtr.Zero)
        {
            _handle = NativeLibrary.Load(ExpectedPath);
            LoadedPath = ExpectedPath;
        }

        return _handle;
    }

    private static string ComputeRid()
    {
        string os = OperatingSystem.IsWindows() ? "win"
            : OperatingSystem.IsMacOS() ? "osx"
            : OperatingSystem.IsAndroid() ? "android"
            : "linux";

        string arch = RuntimeInformation.ProcessArchitecture switch
        {
            Architecture.X64 => "x64",
            Architecture.Arm64 => "arm64",
            Architecture.RiscV64 => "riscv64",
            Architecture.X86 => "x86",
            Architecture.Arm => "arm",
            _ => RuntimeInformation.ProcessArchitecture.ToString().ToLowerInvariant(),
        };

        return $"{os}-{arch}";
    }
}
