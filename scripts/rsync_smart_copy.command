#!/bin/bash
# ============================================================
# rsync 智能拷贝脚本 — Smart Copy with Checksum
# 兼容 macOS 12 (Monterey) ~ macOS 15 (Sequoia)
#
# 使用方式:
#   1. 双击 .command 文件直接运行（会弹出终端窗口让你选择文件夹）
#   2. 通过 Automator Quick Action 右键调用（自动接收选中的文件夹）
#   3. 命令行: ./rsync_smart_copy.command /path/to/source
# ============================================================

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- 函数：打印带颜色的消息 ---
info()    { echo -e "${BLUE}ℹ ${NC}$1"; }
success() { echo -e "${GREEN}✅ ${NC}$1"; }
warn()    { echo -e "${YELLOW}⚠️  ${NC}$1"; }
error()   { echo -e "${RED}❌ ${NC}$1"; }

# --- 函数：选择文件夹（弹出系统对话框）---
pick_folder() {
    local PROMPT="$1"
    local RESULT
    RESULT=$(osascript -e "
        set chosenFolder to choose folder with prompt \"$PROMPT\"
        return POSIX path of chosenFolder
    " 2>/dev/null)
    echo "$RESULT"
}

# --- 函数：显示通知（macOS 原生通知中心）---
notify() {
    osascript -e "display notification \"$1\" with title \"rsync Smart Copy\" sound name \"Glass\"" 2>/dev/null
}

# --- 函数：格式化文件大小 ---
format_size() {
    local SIZE=$1
    if [ "$SIZE" -gt 1073741824 ]; then
        echo "$(echo "scale=1; $SIZE/1073741824" | bc) TB"
    elif [ "$SIZE" -gt 1048576 ]; then
        echo "$(echo "scale=1; $SIZE/1048576" | bc) GB"
    elif [ "$SIZE" -gt 1024 ]; then
        echo "$(echo "scale=1; $SIZE/1024" | bc) MB"
    else
        echo "${SIZE} KB"
    fi
}

# ============================================================
# 主流程
# ============================================================

clear
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════╗"
echo "║     rsync Smart Copy with Checksum       ║"
echo "║     兼容 macOS 12 ~ macOS 15             ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# --- 第 1 步：确定源文件夹 ---
# 优先使用命令行参数或 Automator 传入的路径
if [ -n "$1" ] && [ -d "$1" ]; then
    SRC="$1"
    info "源文件夹（来自参数）: $SRC"
else
    info "请在弹出的对话框中选择要拷贝的 [源文件夹]..."
    SRC=$(pick_folder "选择要拷贝的源文件夹（老硬盘上的文件夹）")
    if [ -z "$SRC" ]; then
        error "未选择源文件夹，退出"
        exit 1
    fi
fi

# 确保路径末尾有斜杠
[[ "$SRC" != */ ]] && SRC="${SRC}/"

echo ""
info "源文件夹: ${CYAN}$SRC${NC}"

# --- 第 2 步：确定目标文件夹 ---
info "请在弹出的对话框中选择 [目标文件夹]（新硬盘上的位置）..."
DEST=$(pick_folder "选择目标文件夹（新硬盘上要存放的位置）")
if [ -z "$DEST" ]; then
    error "未选择目标文件夹，退出"
    exit 1
fi

[[ "$DEST" != */ ]] && DEST="${DEST}/"

echo ""
info "目标文件夹: ${CYAN}$DEST${NC}"

# --- 安全检查：源和目标不能相同 ---
if [ "$(cd "$SRC" && pwd)" = "$(cd "$DEST" && pwd)" ]; then
    error "源和目标是同一个文件夹！请重新选择"
    exit 1
fi

# --- 第 3 步：扫描源文件夹 ---
echo ""
info "正在扫描源文件夹..."
FILE_COUNT=$(find "$SRC" -type f 2>/dev/null | wc -l | tr -d ' ')
DIR_COUNT=$(find "$SRC" -type d 2>/dev/null | wc -l | tr -d ' ')
TOTAL_SIZE_KB=$(du -sk "$SRC" 2>/dev/null | cut -f1)
TOTAL_SIZE=$(format_size "$TOTAL_SIZE_KB")

echo ""
echo "  📁 文件夹数量: $DIR_COUNT"
echo "  📄 文件数量:   $FILE_COUNT"
echo "  💾 总大小:     $TOTAL_SIZE"

# --- 第 4 步：检查目标盘剩余空间 ---
DEST_VOLUME=$(df "$DEST" | tail -1 | awk '{print $1}')
DEST_AVAIL_KB=$(df -k "$DEST" | tail -1 | awk '{print $4}')
DEST_AVAIL=$(format_size "$DEST_AVAIL_KB")

echo ""
echo "  🗄️  目标盘剩余: $DEST_AVAIL"

if [ "$TOTAL_SIZE_KB" -gt "$DEST_AVAIL_KB" ]; then
    error "目标盘空间不足！需要 $TOTAL_SIZE，仅剩 $DEST_AVAIL"
    exit 1
fi

# --- 第 5 步：确认执行 ---
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  即将拷贝: ${CYAN}$(basename "${SRC%/}")${NC}"
echo -e "  从: $SRC"
echo -e "  到: $DEST"
echo -e "  模式: rsync --checksum（拷贝时同步校验）"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

read -p "确认开始拷贝？(y/n): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    warn "用户取消操作"
    exit 0
fi

# --- 第 6 步：创建日志文件 ---
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SRC_NAME=$(basename "${SRC%/}")
LOG_FILE="${DEST}rsync_log_${SRC_NAME}_${TIMESTAMP}.txt"

# --- 第 7 步：执行 rsync ---
echo ""
info "开始拷贝，请耐心等待..."
info "日志文件: $LOG_FILE"
echo ""

START_TIME=$(date +%s)

rsync -avh \
    --checksum \
    --progress \
    --stats \
    --log-file="$LOG_FILE" \
    --exclude=".Spotlight-*" \
    --exclude=".fseventsd" \
    --exclude=".Trashes" \
    --exclude=".DS_Store" \
    --exclude=".TemporaryItems" \
    --exclude="Thumbs.db" \
    --exclude="._.* " \
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
    success "全部完成！所有文件校验通过"
    notify "拷贝完成 ✅ 全部 $FILE_COUNT 个文件校验通过，耗时 ${ELAPSED_MIN}分${ELAPSED_SEC}秒"
elif [ $EXIT_CODE -eq 23 ]; then
    warn "拷贝完成，但部分文件无法读取（可能存在坏扇区）"
    warn "请检查日志文件中的错误: $LOG_FILE"
    echo ""
    echo "  无法读取的文件:"
    grep -i "error\|failed\|vanished" "$LOG_FILE" | head -20
    notify "拷贝完成 ⚠️ 部分文件读取失败，请检查日志"
elif [ $EXIT_CODE -eq 24 ]; then
    warn "拷贝完成，但部分文件在传输过程中消失或变化"
    notify "拷贝完成 ⚠️ 部分文件变化，请检查日志"
else
    error "rsync 异常退出，退出码: $EXIT_CODE"
    error "请检查日志: $LOG_FILE"
    notify "拷贝异常 ❌ 退出码 $EXIT_CODE，请检查日志"
fi

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# --- 第 8 步：抽样验证 ---
echo ""
read -p "是否进行抽样验证？随机检查30个文件 (y/n): " DO_CHECK
if [[ "$DO_CHECK" == "y" || "$DO_CHECK" == "Y" ]]; then
    echo ""
    info "抽样验证照片..."
    FAIL_COUNT=0

    find "$DEST" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.heic" -o -iname "*.cr2" -o -iname "*.cr3" \) 2>/dev/null | \
        sort -R | head -30 | while read -r img; do
            if sips -g pixelWidth "$img" > /dev/null 2>&1; then
                echo -e "  ${GREEN}✅${NC} $(basename "$img")"
            else
                echo -e "  ${RED}❌${NC} $(basename "$img")"
                FAIL_COUNT=$((FAIL_COUNT + 1))
            fi
        done

    echo ""
    info "抽样验证视频（如已安装 ffprobe）..."
    if command -v ffprobe &> /dev/null; then
        find "$DEST" -type f \( -iname "*.mp4" -o -iname "*.mov" -o -iname "*.mts" -o -iname "*.avi" \) 2>/dev/null | \
            sort -R | head -10 | while read -r vid; do
                if ffprobe -v error "$vid" > /dev/null 2>&1; then
                    echo -e "  ${GREEN}✅${NC} $(basename "$vid")"
                else
                    echo -e "  ${RED}❌${NC} $(basename "$vid")"
                fi
            done
    else
        warn "ffprobe 未安装，跳过视频验证（可选安装: brew install ffmpeg）"
    fi

    echo ""
    success "抽样验证完成"
fi

echo ""
info "日志已保存: $LOG_FILE"
echo ""
read -p "按回车键关闭窗口..."
