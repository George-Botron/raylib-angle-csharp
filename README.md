# raylib-cs with raylib ANGLE / Direct3D11 on Windows

This repo builds a native `raylib.dll` for Windows x64 that uses this path:

```text
raylib-cs -> raylib.dll built for OpenGL ES 2.0 -> ANGLE libEGL/libGLESv2 -> Direct3D11
```

The C# code stays normal raylib-cs code. Direct3D is selected by the native `raylib.dll` you ship beside the C# app.

## Why this is needed

The normal raylib-cs native binary uses desktop OpenGL on Windows. That means old, broken, missing, or RDP-affected OpenGL drivers can cause app startup failures.

ANGLE is a compatibility layer that exposes OpenGL ES/EGL to the app and translates it to backends such as Direct3D 11 on Windows. This repo builds raylib as an OpenGL ES 2.0 desktop library and links it to ANGLE.

## Files produced

The GitHub Action uploads `raylib-angle-direct3d11-win-x64.zip` containing:

```text
native/
  raylib.dll
  libEGL.dll
  libGLESv2.dll
  d3dcompiler_47.dll       optional, copied when available

RaylibAngleSample/
  RaylibAngleSample.exe
  Raylib_cs.dll
  raylib.dll
  libEGL.dll
  libGLESv2.dll
  ...
```

## Build it in GitHub Actions

Go to:

```text
Actions -> Build raylib ANGLE Direct3D11 for raylib-cs -> Run workflow
```

The default raylib ref is:

```text
6.0
```

The workflow does this:

1. Installs ANGLE using `vcpkg install angle:x64-windows`.
2. Clones raylib.
3. Patches raylib's Windows Desktop CMake link step with a whitespace-tolerant regex so `OPENGL_VERSION="ES 2.0"` links to `libEGL.lib` and `libGLESv2.lib`, not `opengl32.lib`.
4. Builds `raylib.dll` as a shared library.
5. Verifies `raylib.dll` directly depends on `libGLESv2.dll`, does not depend on `OPENGL32.dll`, and packages `libEGL.dll` beside it.
6. Builds the included raylib-cs sample.
7. Uploads a zip artifact.

## Use the built Direct3D raylib in another C# project

In your external project, keep using the normal raylib-cs NuGet package:

```xml
<ItemGroup>
  <PackageReference Include="Raylib-cs" Version="7.*" />
</ItemGroup>
```

Then copy these files from the artifact into your project, for example:

```text
native/win-x64/raylib.dll
native/win-x64/libEGL.dll
native/win-x64/libGLESv2.dll
native/win-x64/d3dcompiler_47.dll
```

Add this to your `.csproj`:

```xml
<ItemGroup>
  <None Include="native\win-x64\raylib.dll" CopyToOutputDirectory="PreserveNewest" />
  <None Include="native\win-x64\libEGL.dll" CopyToOutputDirectory="PreserveNewest" />
  <None Include="native\win-x64\libGLESv2.dll" CopyToOutputDirectory="PreserveNewest" />
  <None Include="native\win-x64\d3dcompiler_47.dll" CopyToOutputDirectory="PreserveNewest" Condition="Exists('native\win-x64\d3dcompiler_47.dll')" />
</ItemGroup>
```

Build for Windows x64:

```powershell
dotnet build -c Release -r win-x64 --self-contained false
```

Your output folder must contain:

```text
YourApp.exe
Raylib_cs.dll
raylib.dll
libEGL.dll
libGLESv2.dll
```

## Minimal C# example

```csharp
using Raylib_cs;
using static Raylib_cs.Raylib;

InitWindow(800, 450, "raylib-cs through ANGLE / D3D11");
SetTargetFPS(60);

while (!WindowShouldClose())
{
    BeginDrawing();
    ClearBackground(Color.RayWhite);
    DrawText("raylib-cs + ANGLE / Direct3D11", 40, 40, 24, Color.DarkBlue);
    DrawText($"FPS: {GetFPS()}", 40, 80, 20, Color.DarkGreen);
    EndDrawing();
}

CloseWindow();
```

There is no `UseDirectX()` call in raylib-cs. The Direct3D path is provided by the native DLLs.

## Verify you are really using ANGLE / Direct3D

### Verify the DLL link dependencies

From a Visual Studio Developer PowerShell:

```powershell
dumpbin /dependents .\raylib.dll
```

Expected direct dependency:

```text
libGLESv2.dll
```

Expected packaged runtime files beside `raylib.dll`:

```text
libEGL.dll
libGLESv2.dll
```

Unexpected for this build:

```text
OPENGL32.dll
```

`libEGL.dll` may not appear as a direct dependency of `raylib.dll` in `dumpbin /dependents`. That is acceptable for this build. The important checks are that `raylib.dll` imports `libGLESv2.dll`, does not import `OPENGL32.dll`, and `libEGL.dll` is packaged beside the executable.

### Verify while running

Run your C# app and inspect loaded modules using Visual Studio, Process Explorer, or Process Monitor. You should see:

```text
libEGL.dll
libGLESv2.dll
d3d11.dll
dxgi.dll
```

## RDP behavior

This build usually starts more reliably over RDP than desktop OpenGL because it uses Direct3D through ANGLE. It may still use WARP/software rendering unless the host is configured to expose the hardware GPU to Remote Desktop sessions.

## Notes and limitations

- This is Windows x64 only.
- This uses raylib's GLFW desktop platform with OpenGL ES 2.0 context creation.
- This repo patches raylib to request ANGLE's D3D11 backend through GLFW using `GLFW_ANGLE_PLATFORM_TYPE_D3D11`.
- Confirm the runtime path with Process Explorer, Visual Studio Modules, or Process Monitor. You should see `libEGL.dll`, `libGLESv2.dll`, `d3d11.dll`, and `dxgi.dll` loaded.
- Keep the native files beside the `.exe`; do not put them only in the source folder.
- The raylib-cs NuGet may copy its own `raylib.dll`. Your custom `raylib.dll` must be the one in the final output directory.

## Troubleshooting

### App starts but still loads `opengl32.dll`

Your custom native `raylib.dll` was overwritten or not copied. Check the final output folder and run:

```powershell
dumpbin /dependents .\bin\Release\net10.0-windows\win-x64\raylib.dll
```

### Missing `libEGL.dll` or `libGLESv2.dll`

Copy them beside your `.exe`. They must be in the same folder as `raylib.dll`, or otherwise resolvable by the Windows DLL loader.

### Missing `d3dcompiler_47.dll`

Modern Windows usually has it in `System32`, but self-contained app folders can include it. If the workflow copied it into the artifact, ship it beside the app.

### Black window or crash at `InitWindow`

First verify dependencies with `dumpbin`. Then use Process Monitor to check whether Windows failed to load a DLL. Common causes are architecture mismatch, overwritten `raylib.dll`, missing ANGLE DLLs, or using a raylib version whose CMake layout changed and the patch did not apply correctly.


## Maintainer note: previous patch failure

An earlier version of `scripts/build_raylib_angle.py` looked for one exact single-line CMake string in `cmake/LibraryConfigurations.cmake`. That failed on raylib 5.5/6.0 when the same block was formatted differently. The current script uses a whitespace-tolerant regex and prints nearby CMake lines if patching fails again.


## Notes about the Python build scripts

The build logic is in Python now, not PowerShell:

```text
scripts/build_raylib_angle.py
scripts/verify_angle_raylib.py
```

The root fix is that the D3D11 hint patch no longer assumes raylib's GLFW code lives in `src/rcore.c`. raylib 6.0 uses the platform-split backend under `src/platforms/rcore_desktop_glfw.c`; the Python script searches raylib platform sources for the actual `glfwInit(...)` call and inserts `glfwInitHint(GLFW_ANGLE_PLATFORM_TYPE, GLFW_ANGLE_PLATFORM_TYPE_D3D11);` immediately before it.

Correct native verification:

```text
raylib.dll must import libGLESv2.dll
raylib.dll must not import OPENGL32.dll
libEGL.dll must be packaged beside raylib.dll
libEGL.dll does not have to appear as a direct dumpbin dependency of raylib.dll
```
