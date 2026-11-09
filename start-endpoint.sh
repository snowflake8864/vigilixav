#!/bin/bash
# 启动 /opt/EndpointSecurityApp/EndpointSecurityApp
# 用法:
#   sudo ./start-endpoint.sh           # 正常启动 (run.sh)
#   sudo ./start-endpoint.sh --hidden  # 隐藏到托盘 (run-hidden.sh)
set -e

BUNDLE_DIR="/opt/EndpointSecurityApp"
MODE="${1:-}"

if [ "$MODE" = "--hidden" ]; then
    LAUNCHER="$BUNDLE_DIR/run-hidden.sh"
else
    LAUNCHER="$BUNDLE_DIR/run.sh"
fi

if [ ! -x "$LAUNCHER" ]; then
    echo "错误: $LAUNCHER 不存在或不可执行"
    exit 1
fi

# 如果当前就是普通用户，直接启动
if [ "$EUID" -ne 0 ] && [ "$(id -u)" -ge 1000 ]; then
    echo "以当前用户启动 $LAUNCHER ..."
    exec nohup "$LAUNCHER" > /dev/null 2>&1 &
    echo "已启动 (PID $!)"
    exit 0
fi

# root 用户：需要降权到真实用户
if [ -n "$SUDO_USER" ]; then
    TARGET_USER="$SUDO_USER"
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    # systemd 等场景，取第一个人类用户 (UID >= 1000)
    for u in $(awk -F: '$3>=1000 && $3<65534 {print $1; exit}' /etc/passwd); do
        TARGET_USER="$u"
    done
    if [ -z "$TARGET_USER" ]; then
        echo "错误: 找不到非系统用户"
        exit 1
    fi
    USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
fi

echo "以 $TARGET_USER 身份启动 $LAUNCHER ..."

if command -v python3 >/dev/null 2>&1; then
    setsid -f python3 -c "
import os, pwd
pw = pwd.getpwnam('$TARGET_USER')
os.initgroups(pw.pw_name, pw.pw_gid)
os.setgid(pw.pw_gid)
os.setuid(pw.pw_uid)
os.environ['HOME'] = pw.pw_dir
os.environ['USER'] = pw.pw_name
os.environ['LOGNAME'] = pw.pw_name
os.environ['SHELL'] = pw.pw_shell
os.environ.setdefault('DISPLAY', '${DISPLAY:-:0}')
os.environ.setdefault('XAUTHORITY', '${XAUTHORITY:-$USER_HOME/.Xauthority}')
os.execvpe('nohup', ['nohup', '$LAUNCHER'], os.environ)
" > /dev/null 2>&1 &
    echo "已启动 (python3)"

elif command -v perl >/dev/null 2>&1; then
    setsid -f perl -e '
($name,$passwd,$uid,$gid,$quota,$comment,$gcos,$dir,$shell) = getpwnam($ARGV[0]);
$( = $) = $gid;
$> = $< = $uid;
$ENV{HOME} = $dir;
$ENV{USER} = $ENV{LOGNAME} = $name;
$ENV{SHELL} = $shell;
$ENV{DISPLAY} ||= $ARGV[1];
$ENV{XAUTHORITY} ||= $ARGV[2];
exec "nohup", $ARGV[3];
' "$TARGET_USER" "${DISPLAY:-:0}" "${XAUTHORITY:-$USER_HOME/.Xauthority}" "$LAUNCHER" > /dev/null 2>&1 &
    echo "已启动 (perl)"

else
    echo "注意: 无 python3/perl，使用 sudo 降权"
    sudo -b -u "$TARGET_USER" \
        DISPLAY="${DISPLAY:-:0}" \
        XAUTHORITY="${XAUTHORITY:-$USER_HOME/.Xauthority}" \
        nohup "$LAUNCHER" > /dev/null 2>&1
    echo "已启动 (sudo)"
fi
