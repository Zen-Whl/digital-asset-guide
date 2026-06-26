#!/bin/bash
# ============================================================
# rsync 镜像同步脚本 — Mirror Sync (12TB-A → 12TB-B)
# 用途：两块大盘之间的定期增量同步
# 兼容 macOS 12 ~ macOS 15
#
# 与 rsync_smart_copy.command 的区别：
#   smart_copy   → 只增不删，适合从老盘迁移数据（安全第一）
#   mirror_sync  → 完全镜像，适合两块大盘保持一致（含删除同步）
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${BLUE}ℹ ${NC}$1"; }
success() { echo -e "${GREEN}✅ ${NC}$1"; }
warn()    { echo -e "${YELLOW}⚠️  ${NC}$1"; }
error()   { echo -e "${RED}❌ ${NC}$1"; }

pick_folder() {
    osascript -e "
        set chosenFolder to choose folder with prompt \"$1\"
        return POSIX path of chosenFolder
    " 2>/dev/null
}

notify() {
    osascript -e "display notification \"$1\" with title \"Mirror Sync\" sound name \"Glass\"" 2>/dev/null
}

clear
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════╗"
echo "║       rsync Mirror Sync                  ║"
echo "║       两块大盘定期镜像同步               ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# --- 选择源和目标 ---
if [ -n "$1" ] && [ -d "$1" ]; then
    SRC="$1"
else
    info "请选择 [主存储盘] 的同步目录（源）..."
    SRC=$(pick_folder "选择主存储盘上要同步的文件夹（例如 12TB-A 的根目录）")
    [ -z "$SRC" ] && { error "未选择源文件夹"; exit 1; }
fi

if [ -n "$2" ] && [ -d "$2" ]; then
    DEST="$2"
else
    info "请选择 [镜像盘] 的同步目录（目标）..."
    DEST=$(pick_folder "选择镜像盘上对应的文件夹（例如 12TB-B 的根目录）")
    [ -z "$DEST" ] && { error "未选择目标文件夹"; exit 1; }
fi

[[ "$SRC" != */ ]] && SRC="${SRC}/"
[[ "$DEST" != */ ]] && DEST="${DEST}/"

if [ "$(cd "$SRC" && pwd)" = "$(cd "$DEST" && pwd)" ]; then
    error "源和目标是同一个文件夹！"
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${DEST}mirror_sync_log_${TIMESTAMP}.txt"

# ============================================================
# 第 1 步：强制 dry-run 预览（不可跳过）
# ============================================================
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  源（主盘）: ${CYAN}$SRC${NC}"
echo -e "  目标（镜像）: ${CYAN}$DEST${NC}"
echo -e "  模式: ${RED}完全镜像（会删除目标盘上多余的文件）${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
info "第 1 步：预览变更（不实际执行）..."
echo ""

rsync -avhn \
    --checksum \
    --delete \
    --exclude=".Spotlight-*" \
    --exclude=".fseventsd" \
    --exclude=".Trashes" \
    --exclude=".DS_Store" \
    --exclude=".TemporaryItems" \
    --exclude="Thumbs.db" \
    --exclude="rsync_log_*" \
    --exclude="mirror_sync_log_*" \
    "$SRC" "$DEST" 2>&1 | tee /tmp/mirror_preview.txt

# 统计变更
NEW_FILES=$(grep "^>" /tmp/mirror_preview.txt | wc -l | tr -d ' ')
DEL_FILES=$(grep "^deleting" /tmp/mirror_preview.txt | wc -l | tr -d ' ')

echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "  预览结果:"
echo "    新增/更新文件: $NEW_FILES 个"
echo "    将被删除文件: $DEL_FILES 个"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# --- 如果有文件将被删除，额外警告 ---
if [ "$DEL_FILES" -gt 0 ]; then
    echo ""
    warn "以下文件将从镜像盘上删除（因为主盘上已不存在）:"
    echo ""
    grep "^deleting" /tmp/mirror_preview.txt | head -20
    TOTAL_DEL=$(grep "^deleting" /tmp/mirror_preview.txt | wc -l | tr -d ' ')
    if [ "$TOTAL_DEL" -gt 20 ]; then
        echo "  ... 还有 $((TOTAL_DEL - 20)) 个文件未显示"
    fi
    echo ""

    # 删除量超过总文件的 30% 时，强烈警告
    TOTAL_IN_DEST=$(find "$DEST" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$TOTAL_IN_DEST" -gt 0 ]; then
        DEL_RATIO=$((DEL_FILES * 100 / TOTAL_IN_DEST))
        if [ "$DEL_RATIO" -gt 30 ]; then
            echo -e "${RED}╔══════════════════════════════════════════════════╗${NC}"
            echo -e "${RED}║  严重警告：将删除目标盘 ${DEL_RATIO}% 的文件！              ║${NC}"
            echo -e "${RED}║  这通常意味着源路径或目标路径选错了。            ║${NC}"
            echo -e "${RED}║  请仔细确认后再继续。                            ║${NC}"
            echo -e "${RED}╚══════════════════════════════════════════════════╝${NC}"
            echo ""
        fi
    fi
fi

# --- 如果没有任何变更 ---
if [ "$NEW_FILES" -eq 0 ] && [ "$DEL_FILES" -eq 0 ]; then
    success "两块盘已完全一致，无需同步"
    notify "镜像同步：两块盘已完全一致"
    exit 0
fi

# ============================================================
# 第 2 步：确认执行
# ============================================================
echo ""
read -p "确认执行同步？请输入大写 YES 确认: " CONFIRM
if [ "$CONFIRM" != "YES" ]; then
    warn "用户取消操作，未做任何更改"
    exit 0
fi

# ============================================================
# 第 3 步：正式执行
# ============================================================
echo ""
info "开始镜像同步..."
START_TIME=$(date +%s)

rsync -avh \
    --checksum \
    --delete \
    --progress \
    --stats \
    --log-file="$LOG_FILE" \
    --exclude=".Spotlight-*" \
    --exclude=".fseventsd" \
    --exclude=".Trashes" \
    --exclude=".DS_Store" \
    --exclude=".TemporaryItems" \
    --exclude="Thumbs.db" \
    --exclude="rsync_log_*" \
    --exclude="mirror_sync_log_*" \
    "$SRC" "$DEST"

EXIT_CODE=$?
END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))
ELAPSED_MIN=$(( ELAPSED / 60 ))
ELAPSED_SEC=$(( ELAPSED % 60 ))

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "  耗时: ${ELAPSED_MIN} 分 ${ELAPSED_SEC} 秒"

if [ $EXIT_CODE -eq 0 ]; then
    success "镜像同步完成！两块盘现在完全一致"
    notify "镜像同步完成 ✅ 耗时 ${ELAPSED_MIN}分${ELAPSED_SEC}秒"
else
    warn "同步完成但有异常，退出码: $EXIT_CODE"
    warn "请检查日志: $LOG_FILE"
    notify "镜像同步异常 ⚠️ 请检查日志"
fi

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
info "日志已保存: $LOG_FILE"
echo ""
read -p "按回车键关闭窗口..."
