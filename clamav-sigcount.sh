#!/bin/bash
# clamav-sigcount.sh - 统计 ClamAV 病毒库总签名数
# 使用 sigtool 直接读取数据库文件元数据，不依赖 clamd 运行或日志

CLAMAV_BINDIR="/opt/clamav/bin"

# 获取数据库目录
DB_DIR=$(grep -i "^DatabaseDirectory" /opt/clamav/etc/clamd.conf 2>/dev/null | awk '{print $2}')
[ -z "$DB_DIR" ] && DB_DIR="/opt/clamav/var/lib/clamav"

total=0
found=0

printf "%-20s  %-10s  %-10s  %s\n" "数据库文件" "版本号" "签名数" "构建时间"
printf "%-20s  %-10s  %-10s  %s\n" "$(printf '%0.s-' {1..20})" "$(printf '%0.s-' {1..10})" "$(printf '%0.s-' {1..10})" "$(printf '%0.s-' {1..20})"

for f in "$DB_DIR"/*.cvd "$DB_DIR"/*.cld "$DB_DIR"/*.cud; do
    [ -f "$f" ] || continue
    found=$((found + 1))
    info=$("$CLAMAV_BINDIR/sigtool" --info "$f" 2>/dev/null)
    [ -z "$info" ] && continue

    fname=$(basename "$f")
    version=$(echo "$info" | awk '/^Version:/{print $2}')
    sigs=$(echo "$info" | awk '/^Signatures:/{print $2}')
    buildtime=$(echo "$info" | awk -F': ' '/^Build time:/{print $2}')

    sigs=${sigs:-0}
    total=$((total + sigs))
    printf "%-20s  %-10s  %-10s  %s\n" "$fname" "v$version" "$sigs" "$buildtime"
done

[ "$found" -eq 0 ] && echo "错误: 未在 $DB_DIR 中找到任何 .cvd/.cld/.cud 数据库文件" && exit 1

printf "%-20s  %-10s  %-10s\n" "合计" "" "$total"
echo ""
echo "病毒库目录: $DB_DIR"
echo "数据库文件数: $found"
echo "总签名数: $total"
