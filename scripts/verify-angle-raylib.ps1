param(
    [string]$NativeDir = "$PSScriptRoot/../artifacts/raylib-angle-win-x64"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$NativeDir = [IO.Path]::GetFullPath($NativeDir)
$RaylibDll = Join-Path $NativeDir "raylib.dll"

foreach ($file in "raylib.dll", "libEGL.dll", "libGLESv2.dll") {
    $path = Join-Path $NativeDir $file
    if (!(Test-Path $path)) { throw "Missing $path" }
}

$dumpbin = Get-Command dumpbin.exe -ErrorAction SilentlyContinue
if (!$dumpbin) {
    throw "dumpbin.exe not found. Run under a Visual Studio Developer PowerShell or use ilammy/msvc-dev-cmd in GitHub Actions."
}

$deps = & dumpbin /dependents $RaylibDll | Out-String
Write-Host $deps

if ($deps -notmatch "libEGL\.dll") { throw "raylib.dll does not depend on libEGL.dll; this is not an ANGLE build." }
if ($deps -notmatch "libGLESv2\.dll") { throw "raylib.dll does not depend on libGLESv2.dll; this is not an ANGLE build." }
if ($deps -match "OPENGL32\.dll") { throw "raylib.dll still depends on OPENGL32.dll; this is probably a desktop OpenGL build, not ANGLE." }

Write-Host "OK: raylib.dll is linked to ANGLE DLLs."
