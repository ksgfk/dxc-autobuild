#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR=""
BUILD_DIR="${SCRIPT_DIR}/build"
CONFIG="Release"
ARTIFACTS_DIR="${SCRIPT_DIR}/artifacts"
ZIP_NAME=""
PARALLEL=4
EXISTING_BUILD=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-dir) PROJECT_DIR="$2"; shift 2 ;;
        --build-dir) BUILD_DIR="$2"; shift 2 ;;
        --config) CONFIG="$2"; shift 2 ;;
        --artifacts-dir) ARTIFACTS_DIR="$2"; shift 2 ;;
        --zip-name) ZIP_NAME="$2"; shift 2 ;;
        --parallel) PARALLEL="$2"; shift 2 ;;
        --existing-build) EXISTING_BUILD=1; shift ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done
[[ -n "$PROJECT_DIR" ]] || { echo '--project-dir is required' >&2; exit 1; }
case "$CONFIG" in Debug|Release|RelWithDebInfo|MinSizeRel) ;; *) exit 1 ;; esac
version=$(python3 -c 'import pathlib,re,sys; print(re.search(r"set\(RADRAY_DXC_PACKAGE_VERSION\s+\"([^\"]+)\"\)",pathlib.Path(sys.argv[1]).read_text()).group(1))' "$PROJECT_DIR/CMakeLists.txt")
expected_name="dxc-macos-arm64-${version}.zip"
[[ -z "$ZIP_NAME" || "$ZIP_NAME" == "$expected_name" ]] || { echo "Expected archive name: $expected_name" >&2; exit 1; }
[[ ! -e "$ARTIFACTS_DIR/$expected_name" ]] || { echo 'Refusing to replace existing package' >&2; exit 1; }
if [[ "$EXISTING_BUILD" == 0 ]]; then
    cmake -S "$PROJECT_DIR" -B "$BUILD_DIR" -G Ninja -C "$PROJECT_DIR/cmake/caches/PredefinedParams.cmake" \
        -DCMAKE_BUILD_TYPE="$CONFIG" -DCMAKE_OSX_ARCHITECTURES=arm64 -DENABLE_SPIRV_CODEGEN=ON \
        -DLIBCLANG_BUILD_STATIC=OFF -DHLSL_INCLUDE_TESTS=OFF -DSPIRV_BUILD_TESTS=OFF -DLLVM_INCLUDE_TESTS=OFF
fi
cmake --build "$BUILD_DIR" --config "$CONFIG" --target dxcompiler dxc dxildll --parallel "$PARALLEL"
python3 "$PROJECT_DIR/utils/package_radray_sdk.py" --build "$BUILD_DIR" --config "$CONFIG" --no-build --out "$ARTIFACTS_DIR" --version "$version"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "artifact=$(cd "$ARTIFACTS_DIR" && pwd)/$expected_name" >> "$GITHUB_OUTPUT"
fi
