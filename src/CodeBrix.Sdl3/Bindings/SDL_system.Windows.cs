// Copyright (c) ppy Pty Ltd <contact@ppy.sh>. Licensed under the MIT Licence.
// See the LICENCE file in the repository root for full licence text.

using System;
// https://learn.microsoft.com/en-us/dotnet/standard/native-interop/best-practices#common-windows-data-types
using LONG = int;
using DWORD = uint;
using UINT = uint;
using HWND = System.IntPtr;
using WPARAM = System.UIntPtr;
using LPARAM = System.IntPtr;

namespace CodeBrix.Sdl3; //was previously: SDL;

// https://learn.microsoft.com/en-us/windows/win32/api/windef/ns-windef-point
public struct POINT
{
    public LONG x;
    public LONG y;
}

// https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-msg
public struct MSG
{
    public HWND hwnd;
    public UINT message;
    public WPARAM wParam;
    public LPARAM lParam;
    public DWORD time;
    public POINT pt;
    public DWORD lPrivate;
}
