name: Build raylib ANGLE Direct3D11 for raylib-cs

on:
  workflow_dispatch:
    inputs:
      raylib_ref:
        description: "raylib tag/branch/commit to build"
        required: true
        default: "6.0"
  push:
    branches: [ main, master ]
    paths:
      - ".github/workflows/build-raylib-angle.yml"
      - "scripts/**"
      - "src/**"
      - "README.md"
      - "Directory.Build.props"

env:
  VCPKG_ROOT: C:\vcpkg
  VCPKG_INSTALLATION_ROOT: C:\vcpkg

jobs:
  build-win-x64:
    name: Build Windows x64 ANGLE raylib.dll and C# sample
    runs-on: windows-latest

    steps:
      - name: Checkout this repo
        uses: actions/checkout@v4

      - name: Enable MSVC Developer Command Prompt
        uses: ilammy/msvc-dev-cmd@v1
        with:
          arch: x64

      - name: Setup .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: |
            10.0.x

      - name: Setup vcpkg cache
        uses: actions/cache@v4
        with:
          path: |
            C:\vcpkg\installed
            C:\vcpkg\packages
            C:\vcpkg\buildtrees
            C:\vcpkg\downloads
            C:\Users\runneradmin\AppData\Local\vcpkg\archives
          key: vcpkg-angle-${{ runner.os }}-${{ hashFiles('.github/workflows/build-raylib-angle.yml', 'scripts/**') }}
          restore-keys: |
            vcpkg-angle-${{ runner.os }}-

      - name: Install ANGLE from vcpkg
        shell: pwsh
        run: |
          if (-not (Test-Path C:\vcpkg\vcpkg.exe)) {
            git clone https://github.com/microsoft/vcpkg.git C:\vcpkg
            C:\vcpkg\bootstrap-vcpkg.bat
          }
          C:\vcpkg\vcpkg.exe install angle:x64-windows --vcpkg-root C:\vcpkg

      - name: Build native raylib.dll linked to ANGLE
        shell: pwsh
        run: |
          $ref = "${{ github.event.inputs.raylib_ref }}"
          if ([string]::IsNullOrWhiteSpace($ref)) { $ref = "6.0" }
          ./scripts/build-raylib-angle.ps1 -RaylibRef $ref -VcpkgRoot C:\vcpkg -Triplet x64-windows

      - name: Verify native raylib.dll dependencies
        shell: pwsh
        run: ./scripts/verify-angle-raylib.ps1

      - name: Copy native files into C# sample
        shell: pwsh
        run: |
          New-Item -ItemType Directory -Force -Path src/RaylibAngleSample/native/win-x64 | Out-Null
          Copy-Item artifacts/raylib-angle-win-x64/* src/RaylibAngleSample/native/win-x64/ -Force

      - name: Build C# raylib-cs sample
        shell: pwsh
        run: dotnet build src/RaylibAngleSample/RaylibAngleSample.csproj -c Release -r win-x64 --self-contained false

      - name: Verify sample output contains ANGLE files
        shell: pwsh
        run: |
          $sampleRoot = "src/RaylibAngleSample/bin"
          $sampleOut = Get-ChildItem -Path $sampleRoot -Directory -Recurse |
            Where-Object { Test-Path (Join-Path $_.FullName "RaylibAngleSample.dll") } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1 -ExpandProperty FullName

          if ([string]::IsNullOrWhiteSpace($sampleOut)) {
            Write-Host "Searched under: $sampleRoot"
            Get-ChildItem $sampleRoot -Recurse -ErrorAction SilentlyContinue | Select-Object FullName | Format-Table -AutoSize
            throw "Could not find RaylibAngleSample.dll under $sampleRoot."
          }

          Write-Host "Sample output directory: $sampleOut"
          Get-ChildItem $sampleOut | Format-Table Name, Length

          foreach ($file in "raylib.dll", "libEGL.dll", "libGLESv2.dll") {
            if (-not (Test-Path (Join-Path $sampleOut $file))) { throw "Missing $file in sample output: $sampleOut" }
          }

          "RAYLIB_SAMPLE_OUT=$sampleOut" | Add-Content -Path $env:GITHUB_ENV

      - name: Package artifact
        shell: pwsh
        run: |
          if ([string]::IsNullOrWhiteSpace($env:RAYLIB_SAMPLE_OUT)) { throw "RAYLIB_SAMPLE_OUT was not set by verification step." }
          if (-not (Test-Path $env:RAYLIB_SAMPLE_OUT)) { throw "Sample output not found: $env:RAYLIB_SAMPLE_OUT" }

          New-Item -ItemType Directory -Force -Path package | Out-Null
          Copy-Item artifacts/raylib-angle-win-x64 package/native -Recurse -Force
          Copy-Item $env:RAYLIB_SAMPLE_OUT package/RaylibAngleSample -Recurse -Force
          Copy-Item README.md package/README.md -Force
          Compress-Archive -Path package/* -DestinationPath raylib-angle-direct3d11-win-x64.zip -Force

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: raylib-angle-direct3d11-win-x64
          path: raylib-angle-direct3d11-win-x64.zip
          if-no-files-found: error
