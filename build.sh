#!/bin/bash
set -e

# ============================================================
# Vigilix 编译脚本
# 将 Vigilix 编译并安装到 /opt/vigilixav
# ============================================================
# 依赖说明（编译前需确保以下包已安装）:
#   cmake gcc gcc-c++ make rust cargo
#   openssl-devel libxml2-devel bzip2-devel
#   json-c-devel libcurl-devel check-devel
#   pcre2-devel ncurses-devel zlib-devel
# ============================================================

# 如果非 root 用户，自动通过 sudo 重新执行（安装到 /opt 需要 root 权限）
if [ "$EUID" -ne 0 ]; then
    exec sudo -E "$0" "$@"
fi

# 获取真实用户的 HOME 目录（sudo 后 $HOME 可能指向 /root）
if [ -n "$SUDO_USER" ]; then
    REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    REAL_HOME="$HOME"
fi

# 初始化 Rust 环境（sudo 后 $HOME=/root，需显式设置真实用户的 cargo bin）
export CARGO_HOME="${REAL_HOME}/.cargo"
export RUSTUP_HOME="${REAL_HOME}/.rustup"
if [ -d "${CARGO_HOME}/bin" ]; then
    export PATH="${CARGO_HOME}/bin:$PATH"
fi

# 使用新版 CMake（系统自带的 3.13 不满足 3.14+ 要求）
CMAKE_HOME="${REAL_HOME}/local/cmake-3.22.6-linux-aarch64"

if [ -d "$CMAKE_HOME" ]; then
    export PATH="${CMAKE_HOME}/bin:$PATH"
fi

ARCH=$(uname -m)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
INSTALL_PREFIX="/opt/vigilixav"

# Parse flags
FORCE_REBUILD=0
SKIP_BUILD=0
for arg in "$@"; do
    case "$arg" in
        --rebuild)     FORCE_REBUILD=1 ;;
        --skip-build)  SKIP_BUILD=1 ;;
        *) echo "未知参数: $arg"; echo "用法: $0 [--rebuild] [--skip-build]"; exit 1 ;;
    esac
done

echo "============================================"
echo "  Vigilix 编译脚本"
echo "  安装目录: ${INSTALL_PREFIX}"
echo "============================================"

# ============================================
# 判断是否需要重新编译
# ============================================

NEED_CONFIGURE=0
NEED_BUILD=0
NEED_INSTALL=0

if [ "$SKIP_BUILD" -eq 1 ]; then
    echo ""
    echo "--skip-build: 跳过编译，仅执行安装步骤"
    NEED_CONFIGURE=0
    NEED_BUILD=0
    NEED_INSTALL=1
elif [ -f "$INSTALL_PREFIX/bin/freshvigilix" ] && [ -d "$BUILD_DIR" ]; then
    echo ""
    echo "检测到已有编译产物:"
    echo "  安装目录: $INSTALL_PREFIX (已存在)"
    echo "  编译目录: $BUILD_DIR (已存在)"
    echo ""

    if [ "$FORCE_REBUILD" -eq 1 ]; then
        echo "--rebuild: 强制重新编译"
        NEED_CONFIGURE=1
        NEED_BUILD=1
        NEED_INSTALL=1
    else
        read -p "是否重新编译? [y/N]: " ANS
        if [[ "$ANS" =~ ^[Yy]$ ]]; then
            read -p "是否清理编译目录从头开始? [y/N]: " ANS_CLEAN
            if [[ "$ANS_CLEAN" =~ ^[Yy]$ ]]; then
                NEED_CONFIGURE=1
            fi
            NEED_BUILD=1
            NEED_INSTALL=1
        else
            echo "跳过编译，仅复制依赖库和创建目录..."
            NEED_CONFIGURE=0
            NEED_BUILD=0
            NEED_INSTALL=0
        fi
    fi
else
    NEED_CONFIGURE=1
    NEED_BUILD=1
    NEED_INSTALL=1
fi

# ============================================
# 编译阶段
# ============================================

if [ "$NEED_CONFIGURE" -eq 1 ]; then
    echo ""
    echo "清理旧的 build 目录..."
    rm -rf "$BUILD_DIR"
fi

if [ "$NEED_CONFIGURE" -eq 1 ] || [ "$NEED_BUILD" -eq 1 ]; then
    mkdir -p "$BUILD_DIR"
fi

if [ "$NEED_CONFIGURE" -eq 1 ]; then
    echo ""
    echo "[1/3] CMake 配置..."

    cmake \
        -B "$BUILD_DIR" \
        -S "$SCRIPT_DIR" \
        -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_COMPILER=gcc \
        -DCMAKE_CXX_COMPILER=g++ \
        -DENABLE_APP=ON \
        -DENABLE_MILTER=OFF \
        -DENABLE_CLAMONACC=OFF \
        -DENABLE_SYSTEMD=OFF \
        -DENABLE_TESTS=OFF \
        -DENABLE_EXAMPLES=OFF \
        -DENABLE_MAN_PAGES=OFF \
        -DENABLE_DOXYGEN=OFF \
        -DENABLE_UNRAR=ON \
        -DENABLE_SHARED_LIB=ON \
        -DENABLE_STATIC_LIB=OFF \
        -DENABLE_FUZZ=OFF \
        -DBYTECODE_RUNTIME=interpreter \
        -DAPP_CONFIG_DIRECTORY=etc \
        -DDATABASE_DIRECTORY=var/lib/vigilixav \
        -DOPTIMIZE=ON
fi

if [ "$NEED_BUILD" -eq 1 ]; then
    echo ""
    echo "[2/3] 编译中 (make -j$(nproc))..."
    cmake --build "$BUILD_DIR" -j"$(nproc)"
fi

if [ "$NEED_INSTALL" -eq 1 ]; then
    echo ""
    echo "[3/3] 安装到 ${INSTALL_PREFIX}..."
    cmake --install "$BUILD_DIR"
fi

# ============================================
# 复制系统依赖库 & 创建运行时目录
# ============================================

echo ""
echo "复制系统依赖库..."
# 查找系统 libjson-c
JSONC_LIB=$(find /usr/lib -name "libjson-c.so*" -type f 2>/dev/null | head -1)
if [ -n "$JSONC_LIB" ]; then
    cp -f "$JSONC_LIB" "$INSTALL_PREFIX/lib/" 2>/dev/null || true
fi
if [ -f /usr/lib/aarch64-linux-gnu/libssl.so.1.1 ]; then
    cp -f /usr/lib/aarch64-linux-gnu/libssl.so.1.1 "$INSTALL_PREFIX/lib/" 2>/dev/null || true
fi
if [ -f /usr/lib/aarch64-linux-gnu/libcrypto.so.1.1 ]; then
    cp -f /usr/lib/aarch64-linux-gnu/libcrypto.so.1.1 "$INSTALL_PREFIX/lib/" 2>/dev/null || true
fi
if [ -f /usr/local/lib/libiconv.so.2 ]; then
    cp -f /usr/local/lib/libiconv.so.2 "$INSTALL_PREFIX/lib/" 2>/dev/null || true
    cp -f /usr/local/lib/libiconv.so "$INSTALL_PREFIX/lib/" 2>/dev/null || true
fi

# 创建必要的运行时目录
mkdir -p "$INSTALL_PREFIX/var/lib/vigilixav"
mkdir -p "$INSTALL_PREFIX/var/log/vigilixav"
mkdir -p "$INSTALL_PREFIX/var/run"

echo ""
echo "============================================"
echo "  编译安装完成!"
echo "  安装目录: ${INSTALL_PREFIX}"
echo ""
echo "  源码目录: ${SCRIPT_DIR}"
echo "  编译目录: ${BUILD_DIR}"
echo "============================================"
echo ""
echo "下一步: 运行 package.sh 进行打包/生成服务"
