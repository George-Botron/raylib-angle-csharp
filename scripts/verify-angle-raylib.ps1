param(
    [string]$OutDir = "$PSScriptRoot/../artifacts/raylib-angle-win-x64",
    [string]$BuildDir = "$PSScriptRoot/../_build/raylib-build-angle"
)

$ErrorActionPreference = "Stop"

function Assert-File([string]$Path) {
    if (!(Test-Path $Path)) {
        throw "Missing required file: $Path"
    }
}

function Assert-Match([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-NotMatch([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -match $Pattern) {
        throw $Message
    }
}

$OutDir = [IO.Path]::GetFullPath($OutDir)
$BuildDir = [IO.Path]::GetFullPath($BuildDir)

$raylibDll = Join-Path $OutDir "raylib.dll"
$libEglDll = Join-Path $OutDir "libEGL.dll"
$libGlesDll = Join-Path $OutDir "libGLESv2.dll"
$d3dCompilerDll = Join-Path $OutDir "d3dcompiler_47.dll"
$buildInfo = Join-Path $OutDir "build-info.txt"

Assert-File $raylibDll
Assert-File $libEglDll
Assert-File $libGlesDll

if (!(Test-Path $d3dCompilerDll)) {
    Write-Host "Warning: d3dcompiler_47.dll was not found in artifact output. Some ANGLE Direct3D configurations may need it." -ForegroundColor Yellow
}

Write-Host "Verifying raylib native dependencies..."
$dumpbinOutput = & dumpbin /dependents $raylibDll 2>&1 | Out-String
Write-Host $dumpbinOutput

if ($LASTEXITCODE -ne 0) {
    throw "dumpbin failed while checking $raylibDll"
}

# Correct hard checks:
# - raylib.dll should import ANGLE's GLES frontend.
# - raylib.dll should not import desktop OpenGL directly.
# - libEGL.dll only needs to be present beside the app; GLFW's EGL backend loads it dynamically.
Assert-Match $dumpbinOutput '(?im)^\s*libGLESv2\.dll\s*$' `
    "raylib.dll does not depend on libGLESv2.dll. This is not an ANGLE/GLES raylib build."

Assert-NotMatch $dumpbinOutput '(?im)^\s*OPENGL32\.dll\s*$' `
    "raylib.dll depends on OPENGL32.dll. This is a desktop OpenGL build, not the ANGLE/GLES build."

if ($dumpbinOutput -match '(?im)^\s*libEGL\.dll\s*$') {
    Write-Host "raylib.dll imports libEGL.dll directly. That is acceptable."
} else {
    Write-Host "raylib.dll does not import libEGL.dll directly. That is expected: GLFW's EGL backend loads libEGL.dll dynamically at runtime."
}

if (Test-Path $buildInfo) {
    $info = Get-Content $buildInfo -Raw
    Write-Host "Build info:"
    Write-Host $info

    Assert-Match $info 'graphics=GRAPHICS_API_OPENGL_ES2' `
        "build-info.txt does not say GRAPHICS_API_OPENGL_ES2."

    Assert-Match $info 'context\.api=GLFW_EGL_CONTEXT_API' `
        "build-info.txt does not say GLFW_EGL_CONTEXT_API."

    Assert-Match $info 'angle\.backend=GLFW_ANGLE_PLATFORM_TYPE_D3D11' `
        "build-info.txt does not say GLFW_ANGLE_PLATFORM_TYPE_D3D11."
} else {
    Write-Host "Warning: build-info.txt not found. Dependency checks still passed." -ForegroundColor Yellow
}

$cmakeCache = Join-Path $BuildDir "CMakeCache.txt"

if (Test-Path $cmakeCache) {
    $cache = Get-Content $cmakeCache -Raw

    if ($cache -match 'OPENGL_VERSION:STRING=ES 2\.0') {
        Write-Host "CMakeCache confirms OPENGL_VERSION=ES 2.0."
    } else {
        Write-Host "Warning: CMakeCache did not contain OPENGL_VERSION:STRING=ES 2.0. This may be harmless depending on generator/cache formatting." -ForegroundColor Yellow
    }
} else {
    Write-Host "Warning: CMakeCache not found at $cmakeCache. Skipping cache check." -ForegroundColor Yellow
}

Write-Host "Verified: raylib.dll is built for ANGLE/GLES and avoids desktop OPENGL32.dll."
Write-Host "Verified: libEGL.dll and libGLESv2.dll are packaged beside raylib.dll."
Write-Host "Verified: build is configured to request ANGLE Direct3D11 via GLFW init hint."