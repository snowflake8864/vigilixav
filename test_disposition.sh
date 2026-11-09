#!/bin/bash
#
# VigilixAV 病毒处置功能测试脚本
# 测试 MOVE（隔离）和 REMOVE（删除）命令
# 使用 bash 内建 /dev/tcp，无需外部工具
#
# 用法: ./test_disposition.sh
#

set -uo pipefail

# ============ 配置 ============
VIGILIXD_HOST="127.0.0.1"
VIGILIXD_PORT="3310"
QUARANTINE_DIR="/opt/vigilixav/quarantine"
# 测试目录放在 quarantine 下，vigilixav 用户有完整读写权限
TEST_DIR="$QUARANTINE_DIR/.disposition_test"
CMD_TIMEOUT=3

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

# ============ 工具函数 ============
ok()   { echo -e "  ${GREEN}[PASS]${NC} $1"; PASS=$((PASS+1)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; FAIL=$((FAIL+1)); }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; }

# 通过 TCP 发送命令并读取响应（新行终止协议）
send_cmd_newline() {
    local result
    result=$(timeout "$CMD_TIMEOUT" bash -c "
        exec 3<>/dev/tcp/${VIGILIXD_HOST}/${VIGILIXD_PORT} 2>/dev/null || exit 1
        echo \"\$1\" >&3
        cat <&3
    " _ "$1" 2>/dev/null)
    echo "$result"
}

# 通过 TCP 发送命令并读取响应（空字符终止协议，n 前缀）
send_cmd_nullterm() {
    local result
    result=$(timeout "$CMD_TIMEOUT" bash -c '
        exec 3<>/dev/tcp/'"${VIGILIXD_HOST}"'/'"${VIGILIXD_PORT}"' 2>/dev/null || exit 1
        printf "n%s\0" "$1" >&3
        cat <&3
    ' _ "$1" 2>/dev/null)
    echo "$result"
}

# ============ 初始化 ============
echo "=============================================="
echo "  VigilixAV 病毒处置功能测试"
echo "=============================================="
echo ""

# 检查 vigilixd 是否在监听
echo -n "检查 vigilixd ($VIGILIXD_HOST:$VIGILIXD_PORT) ... "
if timeout 2 bash -c "echo >/dev/tcp/${VIGILIXD_HOST}/${VIGILIXD_PORT}" 2>/dev/null; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}无法连接${NC}"
    echo "请先启动: sudo /opt/vigilixav/sbin/vigilixd --config-file=/opt/vigilixav/etc/vigilixd.conf"
    exit 1
fi

# 确认 PING
echo ""
echo "--- 连通性 ---"
result=$(send_cmd_newline "PING")
if echo "$result" | grep -q "PONG"; then
    ok "PING 新行协议 -> $result"
else
    fail "PING 新行协议 -> $result"
fi

result=$(send_cmd_nullterm "PING")
if echo "$result" | grep -q "PONG"; then
    ok "PING 空字符协议 -> $result"
else
    fail "PING 空字符协议 -> $result"
fi

# 检查配置
if send_cmd_newline "MOVE" | grep -q "COMMAND UNAVAILABLE"; then
    warn "EnableMove=no, MOVE 被禁用，请修改配置后重启"
fi
if send_cmd_newline "REMOVE" | grep -q "COMMAND UNAVAILABLE"; then
    warn "EnableRemove=no, REMOVE 被禁用，请修改配置后重启"
fi

# ============ 准备测试环境 ============
echo ""
echo "--- 准备测试环境 ---"
# 清理
rm -rf "$TEST_DIR"
rm -f "$QUARANTINE_DIR"/test_*.txt*
# 在 quarantine 下创建测试目录 (vigilixav 用户有完整权限)
mkdir -p "$TEST_DIR"

# 创建测试文件
echo "this is virus file for REMOVE test"  > "$TEST_DIR/test_remove.txt"
echo "this is virus file for MOVE test"    > "$TEST_DIR/test_move.txt"
echo "this file has spaces in its name"    > "$TEST_DIR/test space file.txt"
echo "nREMOVE target file"                > "$TEST_DIR/test_nremove.txt"
echo "nMOVE target file"                  > "$TEST_DIR/test_nmove.txt"
# 符号链接测试用
echo "not a virus" > "$TEST_DIR/innocent.txt"

ok "测试目录: $TEST_DIR"
ok "隔离目录: $QUARANTINE_DIR"

# ============ 测试 1: REMOVE 删除文件 ============
echo ""
echo "=============================================="
echo "  测试 1: REMOVE 删除文件"
echo "=============================================="

FILE="$TEST_DIR/test_remove.txt"

# 1a. 确认文件存在
if [ -f "$FILE" ]; then
    ok "1a-测试文件存在"
else
    fail "1a-测试文件存在"
fi

# 1b. REMOVE（新行协议）
result=$(send_cmd_newline "REMOVE $FILE")
echo "  响应: $result"
if echo "$result" | grep -q "REMOVED OK"; then
    ok "1b-REMOVE -> REMOVED OK"
else
    fail "1b-REMOVE -> $result"
fi

# 1c. 确认文件已被删除
if [ ! -f "$FILE" ]; then
    ok "1c-文件已被删除"
else
    fail "1c-文件仍然存在"
fi

# 1d. REMOVE 不存在的文件 → 应返回错误
result=$(send_cmd_newline "REMOVE /opt/vigilixav/quarantine/does_not_exist.txt")
echo "  响应: $result"
if echo "$result" | grep -qi "error\|can't\|No such"; then
    ok "1d-REMOVE 不存在文件 -> 返回错误"
else
    fail "1d-REMOVE 不存在文件 -> $result"
fi

# 1e. REMOVE 无参数 → 命令解析器会拒绝
result=$(send_cmd_newline "REMOVE")
echo "  响应: $result"
# 解析器拒绝 req_arg=1 的命令会返回 UNKNOWN COMMAND 或其他错误
if echo "$result" | grep -qi "unknown\|error\|requires"; then
    ok "1e-REMOVE 无参数 -> 被拒绝: $result"
else
    fail "1e-REMOVE 无参数 -> $result"
fi

# ============ 测试 2: MOVE 隔离文件 ============
echo ""
echo "=============================================="
echo "  测试 2: MOVE 隔离文件"
echo "=============================================="

FILE2="$TEST_DIR/test_move.txt"
quarantine_before=$(ls "$QUARANTINE_DIR" 2>/dev/null | grep -v "^\.disposition_test$" | wc -l)

# 2a. 确认文件存在
if [ -f "$FILE2" ]; then
    ok "2a-测试文件存在"
else
    fail "2a-测试文件存在"
fi

# 2b. MOVE（新行协议）
result=$(send_cmd_newline "MOVE $FILE2")
echo "  响应: $result"
if echo "$result" | grep -q "MOVED OK"; then
    ok "2b-MOVE -> MOVED OK"
else
    fail "2b-MOVE -> $result"
fi

# 2c. 源文件应已移走
if [ ! -f "$FILE2" ]; then
    ok "2c-源文件已被移走"
else
    fail "2c-源文件仍在原地"
fi

# 2d. 文件出现在隔离目录
quarantine_after=$(ls "$QUARANTINE_DIR" 2>/dev/null | grep -v "^\.disposition_test$" | wc -l)
echo "  隔离目录文件数: $quarantine_before -> $quarantine_after"
qfile=$(ls "$QUARANTINE_DIR"/test_move.txt* 2>/dev/null | grep -v "\.disposition_test" | head -1)

if [ -n "$qfile" ] && [ -f "$qfile" ]; then
    ok "2d-已隔离: $(basename "$qfile")"
    # 验证内容
    if cat "$qfile" 2>/dev/null | grep -q "virus file for MOVE test"; then
        ok "2e-隔离文件内容正确"
    else
        fail "2e-隔离文件内容异常"
    fi
    # 验证权限
    perm=$(stat -c "%a" "$qfile" 2>/dev/null)
    if [ "$perm" = "600" ]; then
        ok "2f-隔离文件权限正确(600)"
    else
        warn "隔离文件权限: $perm (期望 600)"
    fi
else
    fail "2d-隔离目录未找到文件"
fi

# 2g. MOVE 无参数
result=$(send_cmd_newline "MOVE")
echo "  响应: $result"
if echo "$result" | grep -qi "unknown\|error\|requires"; then
    ok "2g-MOVE 无参数 -> 被拒绝: $result"
else
    fail "2g-MOVE 无参数 -> $result"
fi

# ============ 测试 3: 空字符终止协议 (n 前缀) ============
echo ""
echo "=============================================="
echo "  测试 3: 空字符终止协议 (n 前缀)"
echo "=============================================="

# 3a. nREMOVE
FILE3="$TEST_DIR/test_nremove.txt"
result=$(send_cmd_nullterm "REMOVE $FILE3")
echo "  响应: '$result'"
if echo "$result" | grep -q "REMOVED OK"; then
    ok "3a-nREMOVE -> REMOVED OK"
else
    fail "3a-nREMOVE -> $result"
fi

if [ ! -f "$FILE3" ]; then
    ok "3b-文件已被删除"
else
    fail "3b-文件仍然存在"
fi

# 3c. nMOVE
FILE4="$TEST_DIR/test_nmove.txt"
result=$(send_cmd_nullterm "MOVE $FILE4")
echo "  响应: '$result'"
if echo "$result" | grep -q "MOVED OK"; then
    ok "3c-nMOVE -> MOVED OK"
else
    fail "3c-nMOVE -> $result"
fi

if [ ! -f "$FILE4" ]; then
    ok "3d-源文件已被隔离"
else
    fail "3d-源文件仍在原地"
fi

# ============ 测试 4: 带空格路径 ============
echo ""
echo "=============================================="
echo "  测试 4: 带空格路径"
echo "=============================================="

SPACE_FILE="$TEST_DIR/test space file.txt"

if [ -f "$SPACE_FILE" ]; then
    result=$(send_cmd_newline "REMOVE $SPACE_FILE")
    echo "  响应: $result"
    if echo "$result" | grep -q "REMOVED OK"; then
        ok "4a-REMOVE 带空格路径 -> REMOVED OK"
    else
        fail "4a-REMOVE 带空格路径 -> $result"
    fi
else
    fail "4a-测试文件不存在"
fi

# ============ 测试 5: 符号链接安全性 ============
echo ""
echo "=============================================="
echo "  测试 5: 符号链接安全性"
echo "=============================================="

SYMLINK_SRC="/etc/passwd"
SYMLINK_DST="$TEST_DIR/evil_symlink"
ln -sf "$SYMLINK_SRC" "$SYMLINK_DST" 2>/dev/null || true

if [ -L "$SYMLINK_DST" ]; then
    ok "5a-符号链接已创建: $SYMLINK_DST -> $SYMLINK_SRC"
else
    fail "5a-符号链接创建失败"
fi

result=$(send_cmd_newline "REMOVE $SYMLINK_DST")
echo "  响应: $result"

if [ -f "$SYMLINK_SRC" ]; then
    ok "5b-/etc/passwd 未被删除（符号链接安全防护有效）"
else
    fail "5b-危险: /etc/passwd 可能被删除了!"
fi

# 但不能通过符号链接绕过路径
if echo "$result" | grep -q "REMOVED OK"; then
    warn "5c-符号链接本身被删除了 (可接受的行为)"
else
    ok "5c-符号链接操作被拒绝（更安全的做法）"
fi

# ============ 测试 6: 重复处置 ============
echo ""
echo "=============================================="
echo "  测试 6: 重复处置"
echo "=============================================="

NONEXIST="$TEST_DIR/already_gone.txt"
result=$(send_cmd_newline "REMOVE $NONEXIST")
echo "  响应: $result"
if echo "$result" | grep -qi "error\|can't\|No such"; then
    ok "6a-重复 REMOVE -> 返回错误"
else
    fail "6a-重复 REMOVE -> $result"
fi

# test_move.txt 已经被移走了
PREV_MOVED="$TEST_DIR/test_move.txt"
result=$(send_cmd_newline "MOVE $PREV_MOVED")
echo "  响应: $result"
if echo "$result" | grep -qi "error\|can't\|No such"; then
    ok "6b-重复 MOVE -> 返回错误"
else
    fail "6b-重复 MOVE -> $result"
fi

# ============ 结果汇总 ============
echo ""
echo "=============================================="
echo "  测试结果汇总"
echo "=============================================="
TOTAL=$((PASS + FAIL))
echo -e "  总计: $TOTAL"
echo -e "  ${GREEN}通过: $PASS${NC}"
if [ $FAIL -gt 0 ]; then
    echo -e "  ${RED}失败: $FAIL${NC}"
fi

# 清理
echo ""
echo "清理测试环境..."
rm -rf "$TEST_DIR"
echo "  测试目录已清理"

echo ""
if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}所有测试通过!${NC}"
    exit 0
else
    echo -e "${RED}存在 $FAIL 个失败用例${NC}"
    exit 1
fi
