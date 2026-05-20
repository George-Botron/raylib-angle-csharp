param(
    [string]$NativeDir = "$PSScriptRoot/../artifacts/raylib-angle-win-x64",
    [string]$RaylibSourceDir = "$PSScriptRoot/../_build/raylib"
)

$ErrorActionPreference = "Stop"
$NativeDir = [IO.Path]::GetFullPath($NativeDir)
$raylibDll = Join-Path $NativeDir "raylib.dll"
$glesDll = Join-Path $NativeDir "libGLESv2.dll"
$eglDll = Join-Path $NativeDir "libEGL.dll"
$buildInfo = Join-Path $NativeDir "build-info.txt"

function Assert-File([string]$Path) {
    if (-not (Test-Path $Path)) { throw "Missing required file: $Path" }
}

Assert-File $raylibDll
Assert-File $glesDll
Assert-File $eglDll

$dumpbin = Get-Command dumpbin.exe -ErrorAction SilentlyContinue
if (-not $dumpbin) { throw "dumpbin.exe was not found. Run after ilammy/msvc-dev-cmd or from VS Developer PowerShell." }

Write-Host "Verifying raylib native dependencies..."
$dumpbinOutput = & dumpbin.exe /dependents $raylibDll
$dumpbinText = $dumpbinOutput -join "`n"
Write-Host $dumpbinText

if ($dumpbinText -notmatch "(?im)^\s*libGLESv2\.dll\s*$") {
    throw "raylib.dll does not import libGLESv2.dll. This is not the ANGLE/OpenGL ES build."
}

if ($dumpbinText -match "(?im)^\s*OPENGL32\.dll\s*$") {
    throw "raylib.dll imports OPENGL32.dll. This is the normal desktop OpenGL build, not the ANGLE/GLES build."
}

if ($dumpbinText -match "(?im)^\s*libEGL\.dll\s*$") {
    Write-Host "raylib.dll directly imports libEGL.dll. Acceptable."
} else {
    Write-Host "raylib.dll does not import libEGL.dll directly. Expected: GLFW's EGL backend can load libEGL.dll dynamically at runtime."
}

if (Test-Path $buildInfo) {
    $info = Get-Content $buildInfo -Raw
    Write-Host "Build info:"
    Write-Host $info
    foreach ($required in @(
        "opengl.version=ES 2.0",
        "graphics=GRAPHICS_API_OPENGL_ES2",
        "context.api=GLFW_EGL_CONTEXT_API",
        "client.api=GLFW_OPENGL_ES_API",
        "angle.backend=GLFW_ANGLE_PLATFORM_TYPE_D3D11"
    )) {
        if ($info -notmatch [regex]::Escape($required)) { throw "build-info.txt is missing: $required" }
    }
} else {
    throw "Missing build-info.txt. The build script did not record the ANGLE/D3D11 configuration."
}

$rcore = Join-Path ([IO.Path]::GetFullPath($RaylibSourceDir)) "src/rcore.c"
if (Test-Path $rcore) {
    $rcoreText = Get-Content $rcore -Raw
    if ($rcoreText -notmatch "GLFW_ANGLE_PLATFORM_TYPE_D3D11") {
        throw "rcore.c does not contain GLFW_ANGLE_PLATFORM_TYPE_D3D11. The build may use ANGLE but does not explicitly request Direct3D11."
    }
}

Write-Host "Verified: raylib.dll imports libGLESv2.dll and avoids desktop OPENGL32.dll."
Write-Host "Verified: libEGL.dll and libGLESv2.dll are packaged beside raylib.dll."
Write-Host "Verified: build requests ANGLE Direct3D11 via GLFW_ANGLE_PLATFORM_TYPE_D3D11."
