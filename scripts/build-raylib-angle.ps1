param(
    [string]$RaylibRef = "6.0",
    [string]$RaylibRepo = "https://github.com/raysan5/raylib.git",
    [string]$VcpkgRoot = "$env:VCPKG_INSTALLATION_ROOT",
    [string]$Triplet = "x64-windows",
    [string]$Configuration = "Release",
    [string]$WorkDir = "$PSScriptRoot/../_build",
    [string]$OutDir = "$PSScriptRoot/../artifacts/raylib-angle-win-x64"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Assert-File([string]$Path) {
    if (!(Test-Path $Path)) { throw "Missing required file: $Path" }
}

function Invoke-LoggedCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [Parameter(Mandatory = $true)][string[]]$CommandArgs
    )

    Write-Host "> $Exe $($CommandArgs -join ' ')"
    & $Exe @CommandArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $Exe $($CommandArgs -join ' ')"
    }
}

function Invoke-GitCloneRaylib {
    param(
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string]$Ref,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    # Fast path for tags/branches.
    Write-Host "> git clone --depth 1 --branch $Ref $Repo $Destination"
    & git clone --depth 1 --branch $Ref $Repo $Destination
    if ($LASTEXITCODE -eq 0) { return }

    Write-Host "Branch/tag clone failed. Retrying as commit or arbitrary ref..."
    Remove-Item -Recurse -Force $Destination -ErrorAction SilentlyContinue
    Invoke-LoggedCommand "git" @("clone", "--depth", "1", $Repo, $Destination)
    Push-Location $Destination
    try {
        & git fetch --depth 1 origin $Ref
        if ($LASTEXITCODE -ne 0) { throw "git fetch failed for ref: $Ref" }
        & git checkout --detach FETCH_HEAD
        if ($LASTEXITCODE -ne 0) { throw "git checkout failed for ref: $Ref" }
    }
    finally {
        Pop-Location
    }
}

$WorkDir = [IO.Path]::GetFullPath($WorkDir)
$OutDir = [IO.Path]::GetFullPath($OutDir)
$RaylibDir = Join-Path $WorkDir "raylib"
$BuildDir = Join-Path $WorkDir "raylib-build-angle"

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
Remove-Item -Recurse -Force $OutDir -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if ([string]::IsNullOrWhiteSpace($VcpkgRoot)) {
    throw "VcpkgRoot is empty. Pass -VcpkgRoot or set VCPKG_INSTALLATION_ROOT."
}

if (!(Test-Path $VcpkgRoot)) {
    throw "VcpkgRoot not found: $VcpkgRoot"
}

$AngleInstalled = Join-Path $VcpkgRoot "installed/$Triplet"
$AngleInclude = Join-Path $AngleInstalled "include"
$AngleLib = Join-Path $AngleInstalled "lib"
$AngleBin = Join-Path $AngleInstalled "bin"

Assert-File (Join-Path $AngleInclude "EGL/egl.h")
Assert-File (Join-Path $AngleInclude "GLES2/gl2.h")
Assert-File (Join-Path $AngleLib "libEGL.lib")
Assert-File (Join-Path $AngleLib "libGLESv2.lib")
Assert-File (Join-Path $AngleBin "libEGL.dll")
Assert-File (Join-Path $AngleBin "libGLESv2.dll")

Remove-Item -Recurse -Force $RaylibDir -ErrorAction SilentlyContinue
Invoke-GitCloneRaylib -Repo $RaylibRepo -Ref $RaylibRef -Destination $RaylibDir

$libraryConfig = Join-Path $RaylibDir "cmake/LibraryConfigurations.cmake"
Assert-File $libraryConfig

# raylib can create an OpenGL ES context when OPENGL_VERSION="ES 2.0".
# The missing Windows Desktop piece is the native link step. raylib normally links
# desktop Windows builds to opengl32. For ANGLE, replace only the Windows OpenGL
# link block with libEGL/libGLESv2 when OPENGL_VERSION is ES 2.0/ES 3.0.
$text = Get-Content $libraryConfig -Raw
$marker = 'Desktop Windows OpenGL ES selected: linking raylib against ANGLE libEGL/libGLESv2'
$pattern = '(?s)elseif\s*\(\s*WIN32\s*\)\s*add_definitions\s*\(\s*-D_CRT_SECURE_NO_WARNINGS\s*\)\s*find_package\s*\(\s*OpenGL\s+QUIET\s*\)\s*set\s*\(\s*LIBS_PRIVATE\s+\$\{OPENGL_LIBRARIES\}\s+winmm\s*\)'
$replacement = @'
elseif (WIN32)
    add_definitions(-D_CRT_SECURE_NO_WARNINGS)
    if (${OPENGL_VERSION} MATCHES "ES 2.0|ES 3.0")
        message(STATUS "Desktop Windows OpenGL ES selected: linking raylib against ANGLE libEGL/libGLESv2")
        find_path(ANGLE_INCLUDE_DIR EGL/egl.h REQUIRED)
        find_library(ANGLE_EGL_LIBRARY NAMES libEGL EGL REQUIRED)
        find_library(ANGLE_GLESV2_LIBRARY NAMES libGLESv2 GLESv2 REQUIRED)
        include_directories(${ANGLE_INCLUDE_DIR})
        add_definitions(-DGLFW_INCLUDE_ES2)
        set(OPENGL_INCLUDE_DIR ${ANGLE_INCLUDE_DIR})
        set(LIBS_PRIVATE ${ANGLE_GLESV2_LIBRARY} ${ANGLE_EGL_LIBRARY} winmm)
    else()
        find_package(OpenGL QUIET)
        set(LIBS_PRIVATE ${OPENGL_LIBRARIES} winmm)
    endif()
'@

if ($text -match $marker) {
    Write-Host "raylib CMake file already contains ANGLE patch marker."
} elseif ([regex]::IsMatch($text, $pattern)) {
    $patched = [regex]::Replace($text, $pattern, $replacement, 1)
    Set-Content -Path $libraryConfig -Value $patched -NoNewline
    Write-Host "Patched $libraryConfig for Windows Desktop + OpenGL ES + ANGLE."
} else {
    Write-Host "Could not find expected WIN32 OpenGL link block in $libraryConfig. Nearby WIN32/OpenGL lines:" -ForegroundColor Yellow
    Select-String -Path $libraryConfig -Pattern "WIN32|OPENGL_LIBRARIES|LIBS_PRIVATE|OpenGL" -Context 2,2 | ForEach-Object { $_.ToString() }
    throw "Could not patch $libraryConfig. raylib CMake file layout changed; update the patch."
}

Remove-Item -Recurse -Force $BuildDir -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

$toolchain = Join-Path $VcpkgRoot "scripts/buildsystems/vcpkg.cmake"
Assert-File $toolchain

Invoke-LoggedCommand "cmake" @(
    "-S", $RaylibDir,
    "-B", $BuildDir,
    "-G", "Visual Studio 17 2022",
    "-A", "x64",
    "-DCMAKE_TOOLCHAIN_FILE=$toolchain",
    "-DVCPKG_TARGET_TRIPLET=$Triplet",
    "-DCMAKE_PREFIX_PATH=$AngleInstalled",
    "-DCMAKE_INCLUDE_PATH=$AngleInclude",
    "-DCMAKE_LIBRARY_PATH=$AngleLib",
    "-DPLATFORM=Desktop",
    "-DOPENGL_VERSION=ES 2.0",
    "-DBUILD_SHARED_LIBS=ON",
    "-DBUILD_EXAMPLES=OFF",
    "-DUSE_AUDIO=ON",
    "-DCMAKE_BUILD_TYPE=$Configuration"
)

Invoke-LoggedCommand "cmake" @("--build", $BuildDir, "--config", $Configuration, "--parallel")

$raylibDll = Get-ChildItem $BuildDir -Recurse -Filter raylib.dll |
    Where-Object { $_.FullName -match "\\$Configuration\\" } |
    Select-Object -First 1
if (!$raylibDll) {
    $raylibDll = Get-ChildItem $BuildDir -Recurse -Filter raylib.dll | Select-Object -First 1
}
if (!$raylibDll) { throw "raylib.dll was not produced." }

Copy-Item $raylibDll.FullName (Join-Path $OutDir "raylib.dll") -Force
Copy-Item (Join-Path $AngleBin "libEGL.dll") (Join-Path $OutDir "libEGL.dll") -Force
Copy-Item (Join-Path $AngleBin "libGLESv2.dll") (Join-Path $OutDir "libGLESv2.dll") -Force

$d3dCompiler = Join-Path $AngleBin "d3dcompiler_47.dll"
if (Test-Path $d3dCompiler) {
    Copy-Item $d3dCompiler (Join-Path $OutDir "d3dcompiler_47.dll") -Force
} else {
    $systemD3D = Join-Path $env:WINDIR "System32/d3dcompiler_47.dll"
    if (Test-Path $systemD3D) { Copy-Item $systemD3D (Join-Path $OutDir "d3dcompiler_47.dll") -Force }
}

$commit = "unknown"
Push-Location $RaylibDir
try { $commit = (& git rev-parse HEAD).Trim() } finally { Pop-Location }

$buildInfo = @"
raylib_ref=$RaylibRef
raylib_commit=$commit
triplet=$Triplet
configuration=$Configuration
graphics_api=OpenGL ES 2.0 via ANGLE
expected_backend=ANGLE Direct3D11 on Windows
built_at_utc=$([DateTime]::UtcNow.ToString("o"))
"@
Set-Content -Path (Join-Path $OutDir "build-info.txt") -Value $buildInfo

Get-ChildItem $OutDir | Sort-Object Name | Format-Table Name, Length
Write-Host "ANGLE raylib output: $OutDir"
