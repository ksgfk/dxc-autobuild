#!/usr/bin/env bash
set -euo pipefail

#
# 用法示例（在仓库根目录执行）：
#   bash ./build_macos_arm64.sh --project-dir ./dxc
# 或自定义参数：
#   bash ./build_macos_arm64.sh --project-dir ./dxc --config Release --artifacts-dir ./out --zip-name dxc.zip
#
# 脚本步骤：
# 1) CMake 配置：
#    cmake . -B <BuildDir> -C ... -DCMAKE_INSTALL_PREFIX=<InstallDir> ...
# 2) 构建：
#    cmake --build <BuildDir> --config Release
# 3) 安装：
#    cmake --build <BuildDir> --config Release --target install-distribution
# 4) 手动复制补充文件：
#    - libdxcompiler.dylib, libdxil.dylib -> lib
# 5) 打包
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── 默认参数 ──
PROJECT_DIR=""
BUILD_DIR="${SCRIPT_DIR}/build"
CONFIG="Release"
ARTIFACTS_DIR="${SCRIPT_DIR}/artifacts"
ZIP_NAME="dxc-macos-arm64.zip"

# ── 解析命令行参数 ──
while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-dir)  PROJECT_DIR="$2";   shift 2 ;;
        --build-dir)    BUILD_DIR="$2";     shift 2 ;;
        --config)       CONFIG="$2";        shift 2 ;;
        --artifacts-dir) ARTIFACTS_DIR="$2"; shift 2 ;;
        --zip-name)     ZIP_NAME="$2";      shift 2 ;;
        *)
            echo "未知参数: $1" >&2
            exit 1
            ;;
    esac
done

if [[ -z "${PROJECT_DIR}" ]]; then
    echo "错误：必须指定 --project-dir <DXC源码目录>" >&2
    exit 1
fi

# 验证 Config 值
case "${CONFIG}" in
    Debug|Release|RelWithDebInfo|MinSizeRel) ;;
    *)
        echo "错误：无效的 Config 值 '${CONFIG}'，可选：Debug, Release, RelWithDebInfo, MinSizeRel" >&2
        exit 1
        ;;
esac

# ── 辅助函数 ──
ensure_dir() {
    [[ -n "$1" ]] && mkdir -p "$1"
}

# 在 BuildDir 中查找文件
find_build_artifact() {
    local name="$1"
    local found
    found=$(find "${BUILD_DIR}" -name "${name}" -type f 2>/dev/null | head -n 1)
    if [[ -z "${found}" ]]; then
        echo "未找到 ${name}（在 ${BUILD_DIR} 下）" >&2
        return 1
    fi
    echo "${found}"
}

# ── 1) 解析构建与产物目录 ──
if [[ -z "${BUILD_DIR}" ]]; then
    if [[ -n "${RUNNER_TEMP:-}" ]]; then
        timestamp=$(date -u +%Y%m%d%H%M%S)
        BUILD_DIR="${RUNNER_TEMP}/dxc-build-${timestamp}"
    else
        BUILD_DIR="${SCRIPT_DIR}/build"
    fi
fi

ensure_dir "${BUILD_DIR}"
ensure_dir "${ARTIFACTS_DIR}"

# 重置 artifacts 目录
echo "::group::Reset artifacts directory"
if [[ -d "${ARTIFACTS_DIR}" ]]; then
    rm -rf "${ARTIFACTS_DIR}"
fi
ensure_dir "${ARTIFACTS_DIR}"
echo "Artifacts reset: ${ARTIFACTS_DIR}"
echo "::endgroup::"

# 定义安装目录 (作为 CMAKE_INSTALL_PREFIX)
INSTALL_DIR="${ARTIFACTS_DIR}/dxc-${CONFIG}"
ensure_dir "${INSTALL_DIR}"

echo "Configure build directory: ${BUILD_DIR}"
echo "Install directory: ${INSTALL_DIR}"

# 获取并行编译线程数
NPROC=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)

# ── 2) CMake 配置 ──
echo "::group::CMake Configure"
cmake_args=(
    "${PROJECT_DIR}"
    -B "${BUILD_DIR}"
    -C "${PROJECT_DIR}/cmake/caches/PredefinedParams.cmake"
    -G "Unix Makefiles"
    "-DCMAKE_BUILD_TYPE=${CONFIG}"
    "-DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}"
    "-DCMAKE_C_COMPILER=clang"
    "-DCMAKE_CXX_COMPILER=clang++"
    -DENABLE_SPIRV_CODEGEN=ON
    -DLIBCLANG_BUILD_STATIC=OFF
    -DHLSL_INCLUDE_TESTS=OFF
    -DSPIRV_BUILD_TESTS=OFF
    -DLLVM_INCLUDE_TESTS=OFF
)
echo "cmake ${cmake_args[*]}"
cmake "${cmake_args[@]}"
echo "::endgroup::"

# ── 3) 构建 ──
echo "::group::CMake Build"
echo "cmake --build ${BUILD_DIR} --config ${CONFIG} -- -j${NPROC}"
cmake --build "${BUILD_DIR}" --config "${CONFIG}" -- -j"${NPROC}"
echo "::endgroup::"

# ── 4) 安装 (install-distribution) ──
echo "::group::CMake Install"
echo "cmake --build ${BUILD_DIR} --config ${CONFIG} --target install-distribution"
cmake --build "${BUILD_DIR}" --config "${CONFIG}" --target install-distribution
echo "::endgroup::"

# ── 5) 手动复制补充文件 ──
echo "::group::Post-Install Copy"

BIN_DIR="${INSTALL_DIR}/bin"
LIB_DIR="${INSTALL_DIR}/lib"
ensure_dir "${BIN_DIR}"
ensure_dir "${LIB_DIR}"

# 复制 libdxcompiler.dylib -> lib（如果 install-distribution 未包含）
if [[ ! -f "${LIB_DIR}/libdxcompiler.dylib" ]]; then
    dylib_path=$(find_build_artifact "libdxcompiler.dylib") || true
    if [[ -n "${dylib_path}" ]]; then
        echo "Copying ${dylib_path} to ${LIB_DIR}"
        cp "${dylib_path}" "${LIB_DIR}/libdxcompiler.dylib"
    fi
fi

# 复制 libdxil.dylib -> lib（如果 install-distribution 未包含）
if [[ ! -f "${LIB_DIR}/libdxil.dylib" ]]; then
    dxil_path=$(find_build_artifact "libdxil.dylib") || true
    if [[ -n "${dxil_path}" ]]; then
        echo "Copying ${dxil_path} to ${LIB_DIR}"
        cp "${dxil_path}" "${LIB_DIR}/libdxil.dylib"
    fi
fi

echo "::endgroup::"

# ── 6) 压缩打包 ──
ZIP_PATH="${ARTIFACTS_DIR}/${ZIP_NAME}"
[[ -f "${ZIP_PATH}" ]] && rm -f "${ZIP_PATH}"

echo "Archiving ${INSTALL_DIR} to ${ZIP_PATH}"
(cd "${INSTALL_DIR}" && zip -r "${ZIP_PATH}" .)

echo "打包完成: ${ZIP_PATH}"

# 在 GitHub Actions 中输出 artifact 路径
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "artifact=${ZIP_PATH}" >> "${GITHUB_OUTPUT}"
fi
