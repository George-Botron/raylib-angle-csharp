#!/usr/bin/env python3
"""Verify the built raylib ANGLE native output."""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path


def repo_root_from_script() -> Path:
    return Path(__file__).resolve().parents[1]


def assert_file(path: Path) -> None:
    if not path.is_file():
        raise FileNotFoundError(f"Missing required file: {path}")
    if path.stat().st_size <= 0:
        raise RuntimeError(f"File is empty: {path}")


def run_capture(args: list[str]) -> str:
    print("> " + " ".join(args), flush=True)
    cp = subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(cp.stdout)
    if cp.returncode != 0:
        raise RuntimeError(f"Command failed with exit code {cp.returncode}: {' '.join(args)}")
    return cp.stdout


def main() -> int:
    root = repo_root_from_script()
    parser = argparse.ArgumentParser(description="Verify raylib ANGLE native output.")
    parser.add_argument("--native-dir", default=str(root / "artifacts" / "raylib-angle-win-x64"))
    parser.add_argument("--raylib-source-dir", default=str(root / "_build" / "raylib"))
    args = parser.parse_args()

    native_dir = Path(args.native_dir).resolve()
    raylib_dll = native_dir / "raylib.dll"
    gles_dll = native_dir / "libGLESv2.dll"
    egl_dll = native_dir / "libEGL.dll"
    build_info_path = native_dir / "build-info.txt"

    for file in [raylib_dll, gles_dll, egl_dll, build_info_path]:
        assert_file(file)

    dumpbin = "dumpbin.exe"
    dump = run_capture([dumpbin, "/dependents", str(raylib_dll)])

    if not re.search(r"(?im)^\s*libGLESv2\.dll\s*$", dump):
        raise RuntimeError("raylib.dll does not import libGLESv2.dll. This is not the ANGLE/OpenGL ES build.")
    if re.search(r"(?im)^\s*OPENGL32\.dll\s*$", dump):
        raise RuntimeError("raylib.dll imports OPENGL32.dll. This is desktop OpenGL, not ANGLE/GLES.")

    if re.search(r"(?im)^\s*libEGL\.dll\s*$", dump):
        print("raylib.dll directly imports libEGL.dll. Acceptable.")
    else:
        print("raylib.dll does not directly import libEGL.dll. Acceptable: GLFW may load EGL dynamically at runtime.")

    info = build_info_path.read_text(encoding="utf-8", errors="replace")
    print("Build info:")
    print(info)
    required = [
        "opengl.version=ES 2.0",
        "graphics=GRAPHICS_API_OPENGL_ES2",
        "context.api=GLFW_EGL_CONTEXT_API",
        "client.api=GLFW_OPENGL_ES_API",
        "angle.backend=GLFW_ANGLE_PLATFORM_TYPE_D3D11",
        "angle.hint.patch.file=",
    ]
    for item in required:
        if item not in info:
            raise RuntimeError(f"build-info.txt is missing: {item}")

    raylib_source_dir = Path(args.raylib_source_dir).resolve()
    patch_file_name = ""
    for line in info.splitlines():
        if line.startswith("angle.hint.patch.file="):
            patch_file_name = line.split("=", 1)[1].strip()
            break
    if patch_file_name:
        patch_file = raylib_source_dir / patch_file_name
        assert_file(patch_file)
        patch_text = patch_file.read_text(encoding="utf-8", errors="replace")
        if "GLFW_ANGLE_PLATFORM_TYPE_D3D11" not in patch_text:
            raise RuntimeError(f"{patch_file} does not contain GLFW_ANGLE_PLATFORM_TYPE_D3D11.")

    print("Verified: raylib.dll imports libGLESv2.dll and avoids OPENGL32.dll.")
    print("Verified: libEGL.dll and libGLESv2.dll are packaged beside raylib.dll.")
    print("Verified: build records an ANGLE Direct3D11 GLFW init hint patch.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
