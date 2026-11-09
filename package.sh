#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCH=$(uname -m)

VERSION="1.1.1136"
CUSTOM_VERSION=""

# Parse flags
FORCE_REBUILD=0
while [ $# -gt 0 ]; do
    case "$1" in
        --rebuild-all) FORCE_REBUILD=1 ;;
        --version)
            CUSTOM_VERSION="$2"
            shift
            ;;
        *) OUTPUT="$1" ;;
    esac
    shift
done

# 如果指定了 --version，覆盖默认版本号
[ -n "$CUSTOM_VERSION" ] && VERSION="$CUSTOM_VERSION"
OUTPUT="${OUTPUT:-ccw-installer-${ARCH}-${VERSION}.sh}"

# 如果非 root 用户，自动通过 sudo 重新执行（安装到 /opt 需要 root 权限）
if [ "$EUID" -ne 0 ]; then
    exec sudo -E "$0" "$@"
fi

# 获取真实用户的 HOME 目录（sudo 后 $HOME 可能指向 /root）
if [ -n "$SUDO_USER" ]; then
    REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    # getent 拿不到 home 时回退到 sudo 自行解析（对数字用户名也有效）
    [ -z "$REAL_HOME" ] && REAL_HOME=$(sudo -u "$SUDO_USER" sh -c 'echo "$HOME"' 2>/dev/null)
else
    REAL_HOME="$HOME"
fi

CACHE_DIR="${SCRIPT_DIR}/.build_cache"
OLD_INSTALLER=$(ls -t ccw-installer-*.sh 2>/dev/null | head -1)
[ -z "$OLD_INSTALLER" ] && OLD_INSTALLER="ccw-installer.sh"

# 组件源路径（可覆盖，默认用 /opt 下的真实路径）
VIGILIXAV_SRC="${VIGILIXAV_SRC:-/opt/vigilixav}"
BUNDLE_SRC="${BUNDLE_SRC:-/opt/EndpointSecurityApp}"

echo "=== Build CcwAV Installer ==="
echo "Version: $VERSION"
echo "Output: $OUTPUT"

# ============================================
# 0. 检测已有安装包，决定是否复用各段 payload
# ============================================

REBUILD_VIGILIXAV=0
REBUILD_BUNDLE=0

if [ -f "$OLD_INSTALLER" ]; then
    OLD_SIZE=$(stat -c%s "$OLD_INSTALLER" 2>/dev/null || echo "?")
    OLD_SIZE_K=$((OLD_SIZE / 1024))
    echo ""
    echo "检测到已有安装包: $OLD_INSTALLER (${OLD_SIZE_K}KB)"
    echo ""

    if [ "$FORCE_REBUILD" -ne 1 ]; then
        read -p "1. 是否重新打包 CcwAV? [y/N]: " ANS_VIGILIXAV
        [[ "$ANS_VIGILIXAV" =~ ^[Yy]$ ]] && REBUILD_VIGILIXAV=1

        if [ -d "$BUNDLE_SRC" ]; then
            read -p "2. 是否重新打包 Bundle? [y/N]: " ANS_BUNDLE
            [[ "$ANS_BUNDLE" =~ ^[Yy]$ ]] && REBUILD_BUNDLE=1
        fi

        echo ""
    else
        REBUILD_VIGILIXAV=1
        REBUILD_BUNDLE=1
    fi
else
    echo ""
    echo "未检测到已有安装包，将完整打包所有组件。"
    echo ""
    REBUILD_VIGILIXAV=1
    REBUILD_BUNDLE=1
fi

# ============================================
# 1. 准备临时目录和缓存
# ============================================

TEMP_DIR="/opt/tmp/vigilixav_package_$$"
PAYLOAD_DIR="/opt/tmp/vigilixav_payloads_$$"
rm -rf "$TEMP_DIR" "$PAYLOAD_DIR"
mkdir -p "$TEMP_DIR" "$PAYLOAD_DIR"
mkdir -p "$CACHE_DIR"

echo ""
echo "CcwAV 源: $VIGILIXAV_SRC"
echo "Bundle 源: $BUNDLE_SRC ($( [ -d "$BUNDLE_SRC" ] && echo '存在' || echo '不存在' ))"

# ============================================
# 2. 从缓存获取不复盘的 payload
# ============================================

get_from_cache() {
    local section_name="$1"
    local cache_file="$CACHE_DIR/${section_name}.tar.xz"
    if [ -f "$cache_file" ]; then
        cp "$cache_file" "$PAYLOAD_DIR/${section_name}.tar.xz"
        echo "  [OK] 从缓存复用 ${section_name} ($(stat -c%s "$cache_file" | awk '{printf "%dKB", $1/1024}'))"
        return 0
    fi
    echo "  [!] 没有 ${section_name} 的缓存，需要重新打包"
    return 1
}

# ============================================
# 3. CcwAV 打包
# ============================================

if [ "$REBUILD_VIGILIXAV" -eq 1 ]; then
    echo ""
    echo "--- 打包 CcwAV ---"

    if [ ! -d "$VIGILIXAV_SRC" ] || [ ! -f "$VIGILIXAV_SRC/bin/freshvigilix" ]; then
        echo "未检测到 $VIGILIXAV_SRC，重新编译安装..."
        cd "${SCRIPT_DIR}/build"
        cmake --install . --prefix "$VIGILIXAV_SRC" || true
    fi

    # 确保 CcwAV 自带的 .so 文件都在（cmake --install 可能因权限问题失败）
    if [ -z "$(ls -A "$VIGILIXAV_SRC/lib/"*.so* 2>/dev/null)" ]; then
        echo "从 build 目录复制 CcwAV 库文件..."
        mkdir -p "$VIGILIXAV_SRC/lib"
        find "${SCRIPT_DIR}/build" -maxdepth 3 \( -name "libvigilixav*.so*" -o -name "libfreshvigilix*.so*" -o -name "libvigilixmspack*.so*" -o -name "libvigilixunrar*.so*" \) -exec cp -a {} "$VIGILIXAV_SRC/lib/" \; 2>/dev/null || true
    fi

    # 复制依赖库
    JSONC_LIB=$(find /usr/lib /usr/lib64 /usr/lib/x86_64-linux-gnu /usr/lib/aarch64-linux-gnu -name "libjson-c.so*" -type f 2>/dev/null | head -1)
    if [ -n "$JSONC_LIB" ]; then
        cp -af "$JSONC_LIB" "$VIGILIXAV_SRC/lib/" 2>/dev/null || true
    fi
    if [ -f "/usr/local/lib/libiconv.so.2" ]; then
        echo "复制 libiconv.so.2..."
        cp -f /usr/local/lib/libiconv.so.2 "$VIGILIXAV_SRC/lib/" 2>/dev/null || true
    fi
    if [ -f "/usr/local/lib/libiconv.so" ]; then
        echo "复制 libiconv.so..."
        cp -f /usr/local/lib/libiconv.so "$VIGILIXAV_SRC/lib/" 2>/dev/null || true
    fi
    for libdir in /usr/lib/aarch64-linux-gnu /usr/lib/x86_64-linux-gnu /usr/lib64; do
        if [ -f "$libdir/libssl.so.1.1" ]; then
            echo "复制 libssl.so.1.1($libdir)..."
            cp -af "$libdir"/libssl.so* "$VIGILIXAV_SRC/lib/" 2>/dev/null || true
        fi
        if [ -f "$libdir/libcrypto.so.1.1" ]; then
            echo "复制 libcrypto.so.1.1($libdir)..."
            cp -af "$libdir"/libcrypto.so* "$VIGILIXAV_SRC/lib/" 2>/dev/null || true
        fi
    done

    # 更新病毒库
    if [ ! -d "$VIGILIXAV_SRC/var/lib/vigilixav" ] || [ -z "$(ls -A $VIGILIXAV_SRC/var/lib/vigilixav/*.cvd 2>/dev/null)" ]; then
        echo "更新病毒库..."
        mkdir -p "$VIGILIXAV_SRC/var/lib/vigilixav"
        mkdir -p "$VIGILIXAV_SRC/var/log/vigilixav"
        chown -R vigilixav:vigilixav "$VIGILIXAV_SRC/var" 2>/dev/null || true
        chmod 755 "$VIGILIXAV_SRC/var/lib/vigilixav"

        cat > "$VIGILIXAV_SRC/etc/freshvigilix.conf" << FRESH_TEMP
DatabaseDirectory $VIGILIXAV_SRC/var/lib/vigilixav
UpdateLogFile $VIGILIXAV_SRC/var/log/vigilixav/freshvigilix.log
LogTime true
Foreground false
DatabaseMirror database.clamav.net
FRESH_TEMP
        "$VIGILIXAV_SRC/bin/freshvigilix" 2>/dev/null || true
    fi

    rm -f "$VIGILIXAV_SRC/var/lib/vigilixav"/*.sign 2>/dev/null || true

    echo "压缩 CcwAV..."
    cp -a "$VIGILIXAV_SRC" "$PAYLOAD_DIR/vigilixav"

    # 剔除 vigilixd 不需要的文件：bin/ 下的工具、头文件、文档、freshvigilix 库、freshclam.dat
    echo "清理 vigilixd 不需要的文件..."
    rm -rf "$PAYLOAD_DIR/vigilixav/bin"
    rm -rf "$PAYLOAD_DIR/vigilixav/include"
    rm -rf "$PAYLOAD_DIR/vigilixav/share"
    rm -f "$PAYLOAD_DIR/vigilixav/var/lib/vigilixav/freshclam.dat"
    rm -f "$PAYLOAD_DIR/vigilixav/etc/freshvigilix.conf" "$PAYLOAD_DIR/vigilixav/etc/freshvigilix.conf.sample"
    rm -f "$PAYLOAD_DIR/vigilixav/lib/libfreshvigilix.so"*
    rm -f "$PAYLOAD_DIR/vigilixav/lib64/libfreshvigilix.so"* 2>/dev/null || true

    # 第三方/用户自建病毒库：把 thirdparty-sigs/ 目录里的签名库一并打进安装包
    THIRDPARTY_DB_DIR="${THIRDPARTY_DB_DIR:-${SCRIPT_DIR}/thirdparty-sigs}"
    if [ -d "$THIRDPARTY_DB_DIR" ] && [ -n "$(ls -A "$THIRDPARTY_DB_DIR" 2>/dev/null)" ]; then
        echo "打包第三方病毒库: $THIRDPARTY_DB_DIR"
        mkdir -p "$PAYLOAD_DIR/vigilixav/var/lib/vigilixav"
        cp -a "$THIRDPARTY_DB_DIR"/. "$PAYLOAD_DIR/vigilixav/var/lib/vigilixav/"
        # 第三方目录里若混入 freshclam.dat / *.sign，同样要剔除
        rm -f "$PAYLOAD_DIR/vigilixav/var/lib/vigilixav/freshclam.dat" 2>/dev/null || true
        rm -f "$PAYLOAD_DIR/vigilixav/var/lib/vigilixav/"*.sign 2>/dev/null || true
        find "$PAYLOAD_DIR/vigilixav/var/lib/vigilixav/" -maxdepth 1 -type f -exec chmod 0644 {} \; 2>/dev/null || true
    fi

    if [ -f "/usr/local/lib/libiconv.so.2" ]; then
        cp -f /usr/local/lib/libiconv.so.2 "$PAYLOAD_DIR/vigilixav/lib/" 2>/dev/null || true
    fi
    if [ -f "/usr/local/lib/libiconv.so" ]; then
        cp -f /usr/local/lib/libiconv.so "$PAYLOAD_DIR/vigilixav/lib/" 2>/dev/null || true
    fi
    for libdir in /usr/lib/aarch64-linux-gnu /usr/lib/x86_64-linux-gnu /usr/lib64; do
        if [ -f "$libdir/libssl.so.1.1" ]; then
            cp -af "$libdir"/libssl.so* "$PAYLOAD_DIR/vigilixav/lib/" 2>/dev/null || true
        fi
        if [ -f "$libdir/libcrypto.so.1.1" ]; then
            cp -af "$libdir"/libcrypto.so* "$PAYLOAD_DIR/vigilixav/lib/" 2>/dev/null || true
        fi
    done
    JSONC_PL=$(find /usr/lib /usr/lib64 /usr/lib/x86_64-linux-gnu /usr/lib/aarch64-linux-gnu -name "libjson-c.so*" -type f 2>/dev/null | head -1)
    if [ -n "$JSONC_PL" ]; then
        cp -af "$JSONC_PL" "$PAYLOAD_DIR/vigilixav/lib/" 2>/dev/null || true
    fi
else
    echo ""
    echo "--- 复用已有 CcwAV payload ---"
    get_from_cache "vigilixav" || REBUILD_VIGILIXAV=1
fi

# ============================================
# 4. Bundle 打包
# ============================================

if [ "$REBUILD_BUNDLE" -eq 1 ] && [ -d "$BUNDLE_SRC" ]; then
    echo "--- 打包 Bundle ---"
    mkdir -p "$PAYLOAD_DIR/EndpointSecurityApp"
    rsync -a --exclude='.git' --exclude='.github' --exclude='*.md' --exclude='LICENSE' --exclude='.gitignore' --exclude='logs' "$BUNDLE_SRC"/ "$PAYLOAD_DIR/EndpointSecurityApp/"

elif [ "$REBUILD_BUNDLE" -eq 0 ]; then
    echo "--- 复用已有 Bundle payload ---"
    get_from_cache "EndpointSecurityApp" || REBUILD_BUNDLE=1
fi

# ============================================
# 6. 压缩各段 payload 并缓存
# ============================================

echo ""
echo "压缩 payload 段..."

if [ -d "$PAYLOAD_DIR/vigilixav" ]; then
    tar -cJf "$PAYLOAD_DIR/vigilixav.tar.xz" -C "$PAYLOAD_DIR" vigilixav
    cp "$PAYLOAD_DIR/vigilixav.tar.xz" "$CACHE_DIR/vigilixav.tar.xz"
    rm -rf "$PAYLOAD_DIR/vigilixav"
fi

if [ -d "$PAYLOAD_DIR/EndpointSecurityApp" ]; then
    tar -cJf "$PAYLOAD_DIR/EndpointSecurityApp.tar.xz" -C "$PAYLOAD_DIR" EndpointSecurityApp
    cp "$PAYLOAD_DIR/EndpointSecurityApp.tar.xz" "$CACHE_DIR/EndpointSecurityApp.tar.xz"
    rm -rf "$PAYLOAD_DIR/EndpointSecurityApp"
fi

# 统计 payload 大小
echo ""
for f in vigilixav.tar.xz EndpointSecurityApp.tar.xz; do
    if [ -f "$PAYLOAD_DIR/$f" ]; then
        SZ=$(stat -c%s "$PAYLOAD_DIR/$f")
        echo "  $f: $((SZ / 1024))KB"
    else
        echo "  $f: [不存在，跳过]"
    fi
done

# ============================================
# 5. 生成安装脚本
# ============================================

echo ""
echo "生成安装脚本..."
cat > "$TEMP_DIR/install.sh" << 'INSTALL_SCRIPT'
#!/bin/bash
set -e

VERSION="1.0.0"

# 获取用户家目录（兼容纯数字用户名）
get_user_home() {
    local user="$1"
    local home
    home=$(getent passwd "$user" | cut -d: -f6 2>/dev/null)
    if [ -z "$home" ]; then
        # getent 失败时回退到 sudo 自行解析（对纯数字用户名也有效）
        home=$(sudo -u "$user" sh -c 'echo "$HOME"' 2>/dev/null)
    fi
    echo "$home"
}

# 删除指定用户的桌面快捷方式（兼容纯数字用户名、XDG 自定义桌面目录）
remove_user_desktop_shortcuts() {
    local user="$1" home d
    home=$(get_user_home "$user")
    [ -z "$home" ] && return 0
    for d in "$home/Desktop" "$home/桌面" "$(sudo -u "$user" xdg-user-dir DESKTOP 2>/dev/null || true)"; do
        [ -n "$d" ] || continue
        rm -f "$d/长城端盾.desktop" "$d/EndpointSecurityApp.desktop" 2>/dev/null || true
    done
    return 0
}

if [ "$1" = "--uninstall" ]; then
    INSTALL_DIR="/opt/vigilixav"

    if [ "$EUID" -ne 0 ]; then
        echo "用法: sudo $0 --uninstall"
        exit 1
    fi

    echo "=== CcwAV 卸载脚本 ==="
    echo ""

    echo "停止服务..."
    systemctl stop vigilixav 2>/dev/null || true
    systemctl disable vigilixav 2>/dev/null || true

    echo "删除服务..."
    rm -f /etc/systemd/system/vigilixav.service
    systemctl daemon-reload

    echo "删除安装目录..."
    rm -rf "$INSTALL_DIR"

    echo "删除共享库配置..."
    rm -f /etc/ld.so.conf.d/vigilixav.conf
    ldconfig

    echo "删除 vigilixav 用户..."
    userdel -r vigilixav 2>/dev/null || true

    if [ -d "/opt/EndpointSecurityApp" ]; then
        echo "正在退出 EndpointSecurityApp..."
        pkill -f "EndpointSecurityApp" 2>/dev/null || true
        sleep 1
        pkill -9 -f "EndpointSecurityApp" 2>/dev/null || true
        echo "删除 Bundle..."
        rm -f /etc/xdg/autostart/endpoint-security.desktop
        rm -f /usr/share/applications/EndpointSecurityApp.desktop
        update-desktop-database /usr/share/applications 2>/dev/null || true
        
        # 使用统一的删除函数删除桌面快捷方式
        if [ -n "$SUDO_USER" ]; then
            remove_user_desktop_shortcuts "$SUDO_USER"
        else
            for u in $(awk -F: '$3>=1000 && $3<65534 {print $1}' /etc/passwd); do
                remove_user_desktop_shortcuts "$u"
            done
        fi
        
        rm -rf /opt/EndpointSecurityApp
        rm -rf /tmp/greatwall-endpoint-security-app*
    fi

    echo ""
    echo "=== 卸载完成 ==="
    exit 0
fi

# --upgrade 模式：非交互式卸载旧版后重新安装
UPGRADE_MODE=0
if [ "$1" = "--upgrade" ]; then
    UPGRADE_MODE=1
    echo "=== CcwAV 升级模式 ==="
    if [ -d "/opt/vigilixav" ]; then
        echo "卸载旧版 CcwAV..."
        systemctl stop vigilixav 2>/dev/null || true
        systemctl disable vigilixav 2>/dev/null || true
        rm -f /etc/systemd/system/vigilixav.service
        systemctl daemon-reload 2>/dev/null || true
        rm -rf /opt/vigilixav
        rm -f /etc/ld.so.conf.d/vigilixav.conf
        ldconfig 2>/dev/null || true
    fi
    if [ -d "/opt/EndpointSecurityApp" ]; then
        echo "正在退出 EndpointSecurityApp..."
        pkill -f "EndpointSecurityApp" 2>/dev/null || true
        sleep 1
        pkill -9 -f "EndpointSecurityApp" 2>/dev/null || true
        rm -f /etc/xdg/autostart/endpoint-security.desktop
        rm -f /usr/share/applications/EndpointSecurityApp.desktop
        update-desktop-database /usr/share/applications 2>/dev/null || true
        
        # 使用统一的删除函数删除桌面快捷方式
        if [ -n "$SUDO_USER" ]; then
            remove_user_desktop_shortcuts "$SUDO_USER"
        else
            for u in $(awk -F: '$3>=1000 && $3<65534 {print $1}' /etc/passwd); do
                remove_user_desktop_shortcuts "$u"
            done
        fi

        # 备份 application.cfg（升级时保留用户配置信息）
        APP_CFG_BACKUP=""
        if [ -f "/opt/EndpointSecurityApp/configs/application.cfg" ]; then
            APP_CFG_BACKUP="/opt/tmp/esa_app_cfg_backup_$$"
            mkdir -p /opt/tmp
            cp -a /opt/EndpointSecurityApp/configs/application.cfg "$APP_CFG_BACKUP"
            echo "已备份 application.cfg -> $APP_CFG_BACKUP"
        fi
        rm -rf /opt/EndpointSecurityApp
        rm -rf /tmp/greatwall-endpoint-security-app*
    fi
fi

if [ "$EUID" -ne 0 ]; then
    echo "用法: sudo $0"
    echo "       sudo $0 --uninstall"
    echo "       sudo $0 --upgrade"
    exit 1
fi

INSTALL_DIR="/opt/vigilixav"
BUNDLE_DIR="/opt/EndpointSecurityApp"
TEMP_DIR="/opt/tmp/vigilixav_install_$$"

echo "=== CcwAV + EndpointSecurityApp 安装脚本 ==="
echo ""

# 检查已安装的组件
[ -d "$INSTALL_DIR" ] && VIGILIXAV_INSTALLED=1 || VIGILIXAV_INSTALLED=0
[ -d "$BUNDLE_DIR" ] && BUNDLE_INSTALLED=1 || BUNDLE_INSTALLED=0

echo "当前状态:"
[ $VIGILIXAV_INSTALLED -eq 0 ] && echo "  - CcwAV: 未安装" || echo "  - CcwAV: 已安装"
[ $BUNDLE_INSTALLED -eq 0 ] && echo "  - Bundle: 未安装" || echo "  - Bundle: 已安装"
echo ""

if [ $UPGRADE_MODE -eq 0 ] && [ $VIGILIXAV_INSTALLED -eq 1 ] && [ $BUNDLE_INSTALLED -eq 1 ]; then
    echo "所有组件已安装，无需任何操作。"
    exit 0
fi

mkdir -p "$TEMP_DIR"
trap "rm -rf $TEMP_DIR" EXIT

# 提取并解压 payload (base64编码，START/END之间为编码数据)
extract_payload() {
    local start_marker="$1"
    local end_marker="$2"
    local name="$3"
    local start_line=$(grep -n "^${start_marker}$" "$0" | tail -1 | cut -d: -f1)
    local end_line=$(grep -n "^${end_marker}$" "$0" | tail -1 | cut -d: -f1)
    if [ -n "$start_line" ] && [ -n "$end_line" ] && [ "$end_line" -gt "$start_line" ]; then
        echo "$name ..."
        sed -n "$((start_line + 1)),$((end_line - 1))p" "$0" | base64 -d | tar -xJf - -C "$TEMP_DIR" && echo "  OK" || { echo "  解压失败!"; exit 1; }
    fi
}

extract_payload "===PAYLOAD_START:VIGILIXAV===" "===PAYLOAD_END:VIGILIXAV===" "[1/2] 解压 CcwAV"
extract_payload "===PAYLOAD_START:BUNDLE===" "===PAYLOAD_END:BUNDLE===" "[2/2] 解压 Bundle"

echo ""
echo "解压完成，开始安装..."
echo ""

# 安装 Bundle
if [ $BUNDLE_INSTALLED -eq 0 ] && [ -d "$TEMP_DIR/EndpointSecurityApp" ]; then
    echo "安装 Bundle..."
    cp -a "$TEMP_DIR/EndpointSecurityApp" "$BUNDLE_DIR"
    chown -R root:root "$BUNDLE_DIR"
    chmod -R a+rwX "$BUNDLE_DIR"
    chmod +x "$BUNDLE_DIR/EndpointSecurityApp" "$BUNDLE_DIR/run.sh" 2>/dev/null || true
    chmod +x "$BUNDLE_DIR/run-hidden.sh" 2>/dev/null || true
    chmod +x "$BUNDLE_DIR/launch.sh" 2>/dev/null || true
    chmod +x "$BUNDLE_DIR/libexec/QtWebEngineProcess" 2>/dev/null || true
    echo "Bundle 已安装到 $BUNDLE_DIR"

    # 升级后还原备份的 application.cfg
    if [ -n "$APP_CFG_BACKUP" ] && [ -f "$APP_CFG_BACKUP" ]; then
        mkdir -p "$BUNDLE_DIR/configs"
        cp -a "$APP_CFG_BACKUP" "$BUNDLE_DIR/configs/application.cfg"
        rm -f "$APP_CFG_BACKUP"
        echo "已还原 application.cfg（保留升级前配置）"
    fi

    # 生成 app.conf 到 /etc/.greatwall_app.conf 供 EndpointSecurityApp 运行时读取配置
    APP_CONF="/etc/.greatwall_app.conf"
    INSTALLER_DIR="$(dirname "$0")"
    # 优先从同目录下的 osec-installer-*.sh 读取 VERSION（升级场景）
    ESA_VERSION="$VERSION"
    OSEC_INSTALLER=$(ls "$INSTALLER_DIR"/osec-installer-*.sh 2>/dev/null | head -1)
    if [ -n "$OSEC_INSTALLER" ] && [ -f "$OSEC_INSTALLER" ]; then
        #OV=$(grep -E '^VERSION=' "$OSEC_INSTALLER" | head -1 | cut -d= -f2-)
        OV=$(strings "$OSEC_INSTALLER" | grep -E '^VERSION=' | head -1 | cut -d= -f2-)
        [ -n "$OV" ] && ESA_VERSION="$OV"
    fi
    echo "VERSION=$ESA_VERSION" > "$APP_CONF"
    echo "  已生成 $APP_CONF (VERSION=$ESA_VERSION)"
    # 从 installer 同级目录读取 config.ini（若有），提取 webAddr；否则用默认值
    WEBADDR="http://10.32.1.52:13000"
    if [ -f "$INSTALLER_DIR/config.ini" ]; then
        WA=$(grep -E '^webAddr=' "$INSTALLER_DIR/config.ini" | head -1 | cut -d= -f2-)
        [ -n "$WA" ] && WEBADDR="$WA"
    fi
    echo "webAddr=$WEBADDR" >> "$APP_CONF"
    echo "  已更新 $APP_CONF (webAddr=$WEBADDR)"

    # 自启动：登录后后台启动（隐藏到托盘）
    mkdir -p /etc/xdg/autostart
    AUTOSTART_EXEC="$BUNDLE_DIR/run-hidden.sh"
    cat > /etc/xdg/autostart/endpoint-security.desktop << DESKTOPEOF
[Desktop Entry]
Type=Application
Name=长城端盾
Exec=$AUTOSTART_EXEC
Path=$BUNDLE_DIR
Icon=$BUNDLE_DIR/logo.png
X-GNOME-Autostart-enabled=true
Comment=长城端点安全
DESKTOPEOF

    # 桌面快捷方式 + 系统应用菜单
    # 优先写桌面文件（所有发行版通用），再同步到 /usr/share/applications（如果目录存在）
    DESKTOP_CONTENT="[Desktop Entry]
Version=1.0
Type=Application
Name=长城端盾
GenericName=Endpoint Security
Comment=长城端点安全
Exec=$BUNDLE_DIR/run.sh %U
TryExec=$BUNDLE_DIR/run.sh
Path=$BUNDLE_DIR
Icon=$BUNDLE_DIR/logo.png
Terminal=false
Categories=Utility;Security;System;
Keywords=security;antivirus;scan;vigilix;
StartupNotify=true
StartupWMClass=EndpointSecurityApp
SingleMainWindow=true"

    # 桌面快捷方式：优先通过 SUDO_USER（sudo 场景），否则遍历所有人类用户（systemd 场景）
    # 使用 get_user_home 函数获取家目录（兼容纯数字用户名）
    resolve_desktop_dir() {
        local user="$1" home="$2" d
        if command -v xdg-user-dir >/dev/null 2>&1; then
            d=$(sudo -u "$user" xdg-user-dir DESKTOP 2>/dev/null || true)
            [ -n "$d" ] && [ -d "$d" ] && { echo "$d"; return 0; }
        fi
        for d in "$home/Desktop" "$home/桌面"; do
            [ -d "$d" ] && { echo "$d"; return 0; }
        done
        return 0
    }

    if [ -n "$SUDO_USER" ]; then
        USER_HOME=$(get_user_home "$SUDO_USER")
        DESKTOP_DIR=$(resolve_desktop_dir "$SUDO_USER" "$USER_HOME")
        if [ -n "$DESKTOP_DIR" ]; then
            USER_DESK_FILE="$DESKTOP_DIR/EndpointSecurityApp.desktop"
            echo "$DESKTOP_CONTENT" > "$USER_DESK_FILE"
            chown "$SUDO_USER:$(id -gn "$SUDO_USER" 2>/dev/null || echo "$SUDO_USER")" "$USER_DESK_FILE" 2>/dev/null || true
            chmod 0755 "$USER_DESK_FILE"
            sudo -u "$SUDO_USER" gio set "$USER_DESK_FILE" "metadata::trusted" true 2>/dev/null || true
            echo ">> 桌面图标: $USER_DESK_FILE"
            echo ">> .desktop 内容:"
            cat "$USER_DESK_FILE"
        else
            echo ">> 桌面图标: 未找到桌面目录（user=$SUDO_USER home=${USER_HOME:-空}），跳过桌面快捷方式"
        fi
    else
        # systemd/agent_manager 场景：无 SUDO_USER，遍历人类用户（UID>=1000）
        echo ">> 未检测到 SUDO_USER，扫描人类用户..."
        for u in $(awk -F: '$3>=1000 && $3<65534 {print $1}' /etc/passwd); do
            USER_HOME=$(get_user_home "$u")
            DESKTOP_DIR=$(resolve_desktop_dir "$u" "$USER_HOME")
            if [ -n "$DESKTOP_DIR" ]; then
                USER_DESK_FILE="$DESKTOP_DIR/EndpointSecurityApp.desktop"
                echo "$DESKTOP_CONTENT" > "$USER_DESK_FILE"
                chown "$u:$(id -gn "$u" 2>/dev/null || echo "$u")" "$USER_DESK_FILE" 2>/dev/null || true
                chmod 0755 "$USER_DESK_FILE"
                echo ">> 桌面图标: $USER_DESK_FILE"
                echo ">> .desktop 内容:"
                cat "$USER_DESK_FILE"
                break
            fi
        done
    fi

    if [ -d "/usr/share/applications" ]; then
        echo "$DESKTOP_CONTENT" > "/usr/share/applications/EndpointSecurityApp.desktop"
        chmod 0644 "/usr/share/applications/EndpointSecurityApp.desktop"
        update-desktop-database /usr/share/applications 2>/dev/null || true
        echo ">> 系统菜单: /usr/share/applications/EndpointSecurityApp.desktop"
    fi

    echo ">> launch.sh: $([ -x "$BUNDLE_DIR/launch.sh" ] && echo '可执行' || echo '不可执行!')"

    # 安装后立即启动（以真实用户身份，前台启动）
    ESA_LOG="/tmp/ccw-upgrade-$$.log"
    log_esa() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$ESA_LOG"; }
    log_esa "========== EndpointSecurityApp 启动检测 =========="
    log_esa "SUDO_USER='${SUDO_USER:-}'  DISPLAY='${DISPLAY:-}'  EUID=$EUID  HOME=$HOME"

    AUTOSTART_EXEC="$BUNDLE_DIR/run.sh"
    log_esa "AUTOSTART_EXEC=$AUTOSTART_EXEC  (exists=$([ -f "$AUTOSTART_EXEC" ] && echo yes || echo no))"
    TARGET_USER=""
    TARGET_DISPLAY=""

    # 方式1: 通过 sudo 调用，直接使用 SUDO_USER 和 DISPLAY
    if [ -n "$SUDO_USER" ] && [ -n "${DISPLAY:-}" ]; then
        TARGET_USER="$SUDO_USER"
        TARGET_DISPLAY="$DISPLAY"
        log_esa "[方式1] SUDO_USER: TARGET_USER=$TARGET_USER TARGET_DISPLAY=$TARGET_DISPLAY"
    else
        log_esa "[方式1] 跳过 (SUDO_USER空或DISPLAY空)"
    fi

    # 方式2: 通过 loginctl 查找活跃的图形会话
    if [ -z "$TARGET_USER" ]; then
        if command -v loginctl >/dev/null 2>&1; then
            log_esa "[方式2] loginctl 可用，开始扫描会话..."
            SESSIONS=$(loginctl list-sessions --no-legend 2>/dev/null || echo "")
            log_esa "[方式2] 所有会话: $(echo "$SESSIONS" | tr '\n' ' ')"
            for session_id in $(echo "$SESSIONS" | awk '{print $1}'); do
                [ -z "$session_id" ] && continue
                S_STATE=$(loginctl show-session "$session_id" -p State --value 2>/dev/null)
                S_SEAT=$(loginctl show-session "$session_id" -p Seat --value 2>/dev/null)
                S_DISPLAY=$(loginctl show-session "$session_id" -p Display --value 2>/dev/null)
                S_USER=$(loginctl show-session "$session_id" -p User --value 2>/dev/null)
                # loginctl -p User 返回的是 UID，转为用户名
                S_USER_NAME=$(id -nu "$S_USER" 2>/dev/null || echo "$S_USER")
                log_esa "[方式2] session=$session_id state=$S_STATE seat=$S_SEAT display=$S_DISPLAY uid=$S_USER name=$S_USER_NAME"
                if [ "$S_STATE" = "active" ] && [ -n "$S_DISPLAY" ] && [ -n "$S_SEAT" ] && [ -n "$S_USER_NAME" ]; then
                    TARGET_USER="$S_USER_NAME"
                    TARGET_DISPLAY="$S_DISPLAY"
                    log_esa "[方式2] 命中! TARGET_USER=$TARGET_USER TARGET_DISPLAY=$TARGET_DISPLAY"
                    break
                fi
            done
            if [ -z "$TARGET_USER" ]; then
                log_esa "[方式2] 未找到匹配的活跃图形会话"
            fi
        else
            log_esa "[方式2] loginctl 不可用，跳过"
        fi
    fi

    # 方式3: 扫描 /tmp/.X11-unix/
    if [ -z "$TARGET_USER" ]; then
        log_esa "[方式3] 扫描 /tmp/.X11-unix/ ..."
        if [ -d /tmp/.X11-unix ]; then
            for sock in /tmp/.X11-unix/X*; do
                [ -e "$sock" ] || continue
                DN=$(basename "$sock" | sed 's/^X//')
                TARGET_DISPLAY=":${DN}"
                TARGET_USER=$(stat -c '%U' "$sock" 2>/dev/null)
                log_esa "[方式3] sock=$sock display=$TARGET_DISPLAY owner=$TARGET_USER"
                if [ -n "$TARGET_USER" ] && id "$TARGET_USER" >/dev/null 2>&1; then
                    log_esa "[方式3] 命中! TARGET_USER=$TARGET_USER TARGET_DISPLAY=$TARGET_DISPLAY"
                    break
                fi
            done
        else
            log_esa "[方式3] /tmp/.X11-unix/ 不存在"
        fi
    fi

    if [ -n "$TARGET_USER" ] && [ -n "$TARGET_DISPLAY" ]; then
        log_esa "最终决定: 启动 EndpointSecurityApp (用户=$TARGET_USER, DISPLAY=$TARGET_DISPLAY)"
        echo "启动 EndpointSecurityApp (用户=$TARGET_USER, DISPLAY=$TARGET_DISPLAY)..."
        if command -v runuser >/dev/null 2>&1; then
            log_esa "使用 runuser 启动..."
            runuser -u "$TARGET_USER" -- env DISPLAY="$TARGET_DISPLAY" nohup "$AUTOSTART_EXEC" > /tmp/esa-startup.log 2>&1 &
            ESA_PID=$!
            log_esa "runuser 已发起, PID=$ESA_PID"
        elif command -v sudo >/dev/null 2>&1; then
            log_esa "使用 sudo 启动..."
            sudo -u "$TARGET_USER" env DISPLAY="$TARGET_DISPLAY" nohup "$AUTOSTART_EXEC" > /tmp/esa-startup.log 2>&1 &
            ESA_PID=$!
            log_esa "sudo 已发起, PID=$ESA_PID"
        elif command -v su >/dev/null 2>&1; then
            log_esa "使用 su 启动..."
            su "$TARGET_USER" -c "env DISPLAY='$TARGET_DISPLAY' nohup '$AUTOSTART_EXEC' > /tmp/esa-startup.log 2>&1 &" &
            ESA_PID=$!
            log_esa "su 已发起, PID=$ESA_PID"
        else
            log_esa "错误: 缺少 runuser/sudo/su，无法启动"
            echo "无法以用户 $TARGET_USER 身份启动，缺少 runuser/sudo/su"
        fi
        log_esa "========== 启动检测完成 =========="
    else
        log_esa "最终决定: 不启动 (TARGET_USER='$TARGET_USER' TARGET_DISPLAY='$TARGET_DISPLAY')"
        log_esa "========== 启动检测完成 =========="
        echo "未检测到图形会话，EndpointSecurityApp 将在下次登录时通过 autostart 启动"
    fi
elif [ $BUNDLE_INSTALLED -eq 1 ]; then
    echo "Bundle 已存在，跳过安装"
fi

if [ $VIGILIXAV_INSTALLED -eq 1 ] && [ $UPGRADE_MODE -eq 0 ]; then
    echo "CcwAV 已存在，跳过安装"
    SKIP_VIGILIXAV=1
else
    SKIP_VIGILIXAV=0
fi

if [ $SKIP_VIGILIXAV -eq 0 ]; then
    SOURCE_DIR="$TEMP_DIR/vigilixav"

    echo "创建vigilixav用户..."
    if ! id vigilixav &>/dev/null; then
        useradd -r -s /bin/false -d /var/lib/vigilixav -c "Vigilix" vigilixav
        echo "用户vigilixav已创建"
    else
        echo "用户vigilixav已存在"
    fi

    echo "创建目录结构..."
    mkdir -p "$INSTALL_DIR"/{sbin,etc,etc/certs,lib,quarantine,var/lib/vigilixav,var/log/vigilixav,var/run}
    [ -d "$SOURCE_DIR/lib64" ] && mkdir -p "$INSTALL_DIR/lib64"
    chown vigilixav:vigilixav "$INSTALL_DIR/var/run" "$INSTALL_DIR/quarantine"
    chmod 1777 "$INSTALL_DIR/quarantine"

    echo "复制二进制文件..."
    [ -d "$SOURCE_DIR/sbin" ] && cp -a "$SOURCE_DIR"/sbin/* "$INSTALL_DIR/sbin/" || true

    echo "复制配置文件和病毒库..."
    rm -rf /etc/vigilixav 2>/dev/null || true
    cp -a "$SOURCE_DIR"/etc/* "$INSTALL_DIR/etc/"
    [ -d "$SOURCE_DIR/var/lib/vigilixav" ] && [ -n "$(ls -A "$SOURCE_DIR/var/lib/vigilixav/" 2>/dev/null)" ] && cp -a "$SOURCE_DIR"/var/lib/vigilixav/* "$INSTALL_DIR/var/lib/vigilixav/" 2>/dev/null || true

    mkdir -p "$INSTALL_DIR/etc/certs"
    chmod -R 755 "$INSTALL_DIR/etc/certs"
    chmod 644 "$INSTALL_DIR/etc/certs/vigilixav.crt" 2>/dev/null || true
    rm -f "$INSTALL_DIR/var/lib/vigilixav"/*.sign

    echo "复制库文件..."
    if [ -d "$SOURCE_DIR/lib" ] && [ -n "$(ls -A "$SOURCE_DIR/lib" 2>/dev/null)" ]; then
        cp -a "$SOURCE_DIR"/lib/* "$INSTALL_DIR/lib/"
        # 剔除 freshvigilix 库，vigilixd 不需要
        rm -f "$INSTALL_DIR/lib/libfreshvigilix.so"*
    else
        echo "  跳过 (lib 目录为空)"
    fi

    # lib64 目录（x86_64 cmake 默认将 .so 装至此目录）
    if [ -d "$SOURCE_DIR/lib64" ] && [ -n "$(ls -A "$SOURCE_DIR/lib64" 2>/dev/null)" ]; then
        echo "复制 lib64 库文件..."
        cp -a "$SOURCE_DIR"/lib64/* "$INSTALL_DIR/lib64/"
        rm -f "$INSTALL_DIR/lib64/libfreshvigilix.so"*
    fi

    JSONC_LIB=$(find /usr/lib /usr/lib64 /usr/lib/x86_64-linux-gnu /usr/lib/aarch64-linux-gnu -name "libjson-c.so*" -type f 2>/dev/null | head -1)
    if [ -n "$JSONC_LIB" ]; then
        cp -af "$JSONC_LIB" "$INSTALL_DIR/lib/" 2>/dev/null || true
    fi
    if [ -f "/usr/local/lib/libiconv.so.2" ]; then
        cp -f /usr/local/lib/libiconv.so.2 "$INSTALL_DIR/lib/" 2>/dev/null || true
    fi
    if [ -f "/usr/local/lib/libiconv.so" ]; then
        cp -f /usr/local/lib/libiconv.so "$INSTALL_DIR/lib/" 2>/dev/null || true
    fi
    if [ -f "$SOURCE_DIR/lib/libiconv.so.2" ] && [ ! -f "$INSTALL_DIR/lib/libiconv.so.2" ]; then
        cp -f "$SOURCE_DIR/lib/libiconv.so.2" "$INSTALL_DIR/lib/" 2>/dev/null || true
    fi
    if [ -f "$SOURCE_DIR/lib/libiconv.so" ] && [ ! -f "$INSTALL_DIR/lib/libiconv.so" ]; then
        cp -f "$SOURCE_DIR/lib/libiconv.so" "$INSTALL_DIR/lib/" 2>/dev/null || true
    fi

    # 复制 OpenSSL 1.1 库（解决目标机器 OpenSSL 版本不兼容问题）
    for libdir in /usr/lib/aarch64-linux-gnu /usr/lib/x86_64-linux-gnu /usr/lib64; do
        if [ -f "$libdir/libssl.so.1.1" ]; then
            cp -af "$libdir"/libssl.so* "$INSTALL_DIR/lib/" 2>/dev/null || true
        fi
        if [ -f "$libdir/libcrypto.so.1.1" ]; then
            cp -af "$libdir"/libcrypto.so* "$INSTALL_DIR/lib/" 2>/dev/null || true
        fi
    done
    if [ -f "$SOURCE_DIR/lib/libssl.so.1.1" ] && [ ! -f "$INSTALL_DIR/lib/libssl.so.1.1" ]; then
        cp -f "$SOURCE_DIR/lib/libssl.so.1.1" "$INSTALL_DIR/lib/" 2>/dev/null || true
    fi
    if [ -f "$SOURCE_DIR/lib/libcrypto.so.1.1" ] && [ ! -f "$INSTALL_DIR/lib/libcrypto.so.1.1" ]; then
        cp -f "$SOURCE_DIR/lib/libcrypto.so.1.1" "$INSTALL_DIR/lib/" 2>/dev/null || true
    fi

    echo "设置权限和配置..."
    chown -R vigilixav:vigilixav "$INSTALL_DIR/var"
    chown -R root:root "$INSTALL_DIR/sbin" "$INSTALL_DIR/etc"
    chown -R root:root "$INSTALL_DIR/lib"
    [ -d "$INSTALL_DIR/lib64" ] && chown -R root:root "$INSTALL_DIR/lib64"
    chmod 755 "$INSTALL_DIR/var/run" 2>/dev/null || true
    chmod 755 "$INSTALL_DIR/sbin"/* 2>/dev/null || true
    chmod 644 "$INSTALL_DIR/etc"/* 2>/dev/null || true
    chmod 755 "$INSTALL_DIR/lib"/*.so* 2>/dev/null || true
    [ -d "$INSTALL_DIR/lib64" ] && chmod 755 "$INSTALL_DIR/lib64"/*.so* 2>/dev/null || true
    chmod 640 "$INSTALL_DIR/var/log/vigilixav"/*.log 2>/dev/null || true
    chmod 755 "$INSTALL_DIR/var/lib/vigilixav" 2>/dev/null || true

    # 完全重写配置文件，确保路径正确
    cat > "$INSTALL_DIR/etc/vigilixd.conf" << VIGILIXD_EOF
# 基础配置
DatabaseDirectory $INSTALL_DIR/var/lib/vigilixav
LogFile $INSTALL_DIR/var/log/vigilixav/vigilixd.log
LogTime yes
LogSyslog yes
PidFile $INSTALL_DIR/var/run/vigilixd.pid

# 端口和地址
TCPSocket 3310
TCPAddr 127.0.0.1

# Unix Socket 配置
LocalSocket $INSTALL_DIR/var/run/vigilixd.sock
LocalSocketGroup vigilixav
LocalSocketMode 660

# 线程和连接
MaxThreads 8
MaxConnectionQueueLength 15

# 扫描配置
MaxFileSize 200M
MaxRecursion 16
MaxFiles 100000
MaxEmbeddedPE 20M
MaxHTMLNormalize 32M
MaxHTMLNoTags 2M
MaxScriptNormalize 2M
MaxZipTypeRcg 1M
MaxPartitions 128
MaxIconsPE 200

# Stream 设置
StreamMaxLength 1024M
StreamMinPort 20000
StreamMaxPort 32000

# 目录排除
ExcludePath ^/proc
ExcludePath ^/sys
ExcludePath ^/dev
ExcludePath ^/run

# 脱壳和压缩
DisableCache yes
ForceToDisk no
LeaveTemporaryFiles no
TemporaryDirectory /tmp

# 安全设置
User vigilixav
OfficialDatabaseOnly no
BytecodeSecurity TrustSigned
CVDCertsDirectory $INSTALL_DIR/etc/certs

# 日志级别
LogClean yes
LogVerbose yes
VIGILIXD_EOF

    echo "创建systemd服务..."
    cat > /etc/systemd/system/vigilixav.service << SYSTEMD_EOF
[Unit]
Description=Vigilix Antivirus Daemon
After=network.target

[Service]
Type=forking
ExecStartPre=/bin/mkdir -p $INSTALL_DIR/var/run
ExecStart=$INSTALL_DIR/sbin/vigilixd --config-file=$INSTALL_DIR/etc/vigilixd.conf
Restart=always
RestartSec=5
User=root
Group=root

[Install]
WantedBy=multi-user.target
SYSTEMD_EOF

    systemctl daemon-reload
    echo "$INSTALL_DIR/lib" > /etc/ld.so.conf.d/vigilixav.conf
    [ -d "$INSTALL_DIR/lib64" ] && echo "$INSTALL_DIR/lib64" >> /etc/ld.so.conf.d/vigilixav.conf
    ldconfig

    systemctl enable vigilixav

    echo "启动vigilixd服务..."
    systemctl start vigilixav

    # 校验关键 .so 是否到位
    echo ""
    echo "校验库文件..."
    MISSING=""
    for lib in libvigilixav.so libvigilixmspack.so; do
        FOUND=$(find "$INSTALL_DIR/lib" "$INSTALL_DIR/lib64" -maxdepth 1 -name "${lib}*" 2>/dev/null | head -1)
        if [ -n "$FOUND" ]; then
            echo "  OK: $lib"
        else
            echo "  缺失: $lib"
            MISSING="$MISSING $lib"
        fi
    done
    if [ -n "$MISSING" ]; then
        echo ""
        echo "错误: 以下库文件未安装成功，请检查安装脚本输出:"
        echo "       $MISSING"
    fi
fi

echo ""
echo "=== 安装完成 ==="
echo ""

if [ $BUNDLE_INSTALLED -eq 0 ] && [ -d "$BUNDLE_DIR" ]; then
    echo "Bundle: $BUNDLE_DIR"
    echo "  运行: $BUNDLE_DIR/run.sh"
    echo ""
fi

if [ $SKIP_VIGILIXAV -eq 0 ]; then
    echo "CcwAV: $INSTALL_DIR"
    echo "  配置文件: $INSTALL_DIR/etc/vigilixd.conf"
    echo "  启动: systemctl start vigilixav"
else
    echo "CcwAV: 已存在，跳过安装"
fi

echo ""
echo "卸载: sudo $0 --uninstall"
exit 0
INSTALL_SCRIPT

# 将模板中的占位版本号替换为实际版本
sed -i "s/1\.0\.0/$VERSION/g" "$TEMP_DIR/install.sh"

chmod +x "$TEMP_DIR/install.sh"

# ============================================
# 6. 拼接 payload
# ============================================

echo "拼接安装包..."

# 先复制 install 脚本
cp "$TEMP_DIR/install.sh" "$OUTPUT"

# 追加 CcwAV payload (base64编码避免二进制数据问题)
if [ -f "$PAYLOAD_DIR/vigilixav.tar.xz" ]; then
    echo "" >> "$OUTPUT"
    echo "===PAYLOAD_START:VIGILIXAV===" >> "$OUTPUT"
    base64 "$PAYLOAD_DIR/vigilixav.tar.xz" >> "$OUTPUT"
    echo "===PAYLOAD_END:VIGILIXAV===" >> "$OUTPUT"
else
    echo "" >> "$OUTPUT"
    echo "===PAYLOAD_START:VIGILIXAV===" >> "$OUTPUT"
    echo "===PAYLOAD_END:VIGILIXAV===" >> "$OUTPUT"
fi

# 追加 Bundle payload
if [ -f "$PAYLOAD_DIR/EndpointSecurityApp.tar.xz" ]; then
    echo "" >> "$OUTPUT"
    echo "===PAYLOAD_START:BUNDLE===" >> "$OUTPUT"
    base64 "$PAYLOAD_DIR/EndpointSecurityApp.tar.xz" >> "$OUTPUT"
    echo "===PAYLOAD_END:BUNDLE===" >> "$OUTPUT"
else
    echo "" >> "$OUTPUT"
    echo "===PAYLOAD_START:BUNDLE===" >> "$OUTPUT"
    echo "===PAYLOAD_END:BUNDLE===" >> "$OUTPUT"
fi

chmod +x "$OUTPUT"

# 清理临时文件
rm -rf "$TEMP_DIR" "$PAYLOAD_DIR"

echo ""
echo "=== 完成 ==="
echo "安装脚本: $OUTPUT"
SZ=$(stat -c%s "$OUTPUT")
echo "文件大小: $((SZ / 1024))KB"
echo ""
echo "使用方法:"
echo "  sudo $OUTPUT          # 安装"
echo "  sudo $OUTPUT --uninstall  # 卸载"
