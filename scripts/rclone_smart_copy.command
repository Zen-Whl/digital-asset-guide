#!/bin/bash
# ============================================================
# rclone 智能拷贝脚本 — Smart Copy with Checksum (rclone 版)
# 兼容 macOS 12 (Monterey) ~ macOS 15 (Sequoia)
# ============================================================

# --- 校验模式（三选一）---
#   inline : 边拷边校验。rclone 写完每个文件即比对哈希，回读多命中缓存、
#            几乎不额外耗时。日常备份推荐，速度与校验兼顾。【默认】
#   after  : 先快速拷贝(跳过内嵌校验) + 拷完做整盘 rclone check --checksum 全量复校。
#            会把源盘整整再读一遍，更慢，但回读来自物理盘片、能抓盘片级静默损坏。
#            适合"硬盘级归档备份"想要最彻底物理校验时。
#   none   : 只快速拷贝、完全不校验（不推荐，仅用于临时/可重来的数据）。
VERIFY_MODE="inline"

# --- 性能参数（按盘的情况调整）---
# WD 高性能盘等健康机械盘建议 TRANSFERS=4；SSD/NVMe 可 8~16
# 同一块物理盘内部对拷请把 TRANSFERS 调到 1~2，避免磁头来回寻道反而变慢
TRANSFERS=4          # 并行传输的文件数
CHECKERS=16          # 扫描/比对阶段的并行度
MULTI_STREAMS=2      # 单个大文件拆分成几路并行（HDD 建议 1~2，SSD 可 4）
MULTI_CUTOFF="512M"  # 文件超过此大小才启用多路并行

# --- 颜色定义 ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

info()    { echo -e "${BLUE}ℹ ${NC}$1"; }
success() { echo -e "${GREEN}✅ ${NC}$1"; }
warn()    { echo -e "${YELLOW}⚠️  ${NC}$1"; }
error()   { echo -e "${RED}❌ ${NC}$1"; }

pick_folder() {
    local PROMPT="$1" RESULT
    RESULT=$(osascript -e "
        set chosenFolder to choose folder with prompt \"$PROMPT\"
        return POSIX path of chosenFolder
    " 2>/dev/null)
    echo "$RESULT"
}

notify() {
    osascript -e "display notification \"$1\" with title \"rclone Smart Copy\" sound name \"Glass\"" 2>/dev/null
}

format_size() {
    local SIZE=$1
    if [ "$SIZE" -gt 1073741824 ]; then echo "$(echo "scale=1; $SIZE/1073741824" | bc) TB"
    elif [ "$SIZE" -gt 1048576 ]; then echo "$(echo "scale=1; $SIZE/1048576" | bc) GB"
    elif [ "$SIZE" -gt 1024 ]; then echo "$(echo "scale=1; $SIZE/1024" | bc) MB"
    else echo "${SIZE} KB"; fi
}

# ============================================================
clear
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════╗"
echo "║     rclone Smart Copy with Checksum      ║"
echo "║     兼容 macOS 12 ~ macOS 15             ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# --- 第 0 步：检查 rclone ---
if ! command -v rclone &> /dev/null; then
    error "未检测到 rclone"
    echo ""
    echo "  请先安装 rclone，二选一："
    echo -e "    ${CYAN}brew install rclone${NC}"
    echo -e "    ${CYAN}curl https://rclone.org/install.sh | sudo bash${NC}"
    echo ""
    read -p "按回车键退出..."
    exit 1
fi
info "已检测到: ${CYAN}$(rclone version | head -1)${NC}"

case "$VERIFY_MODE" in
    inline) MODE_DESC="边拷边校验（默认，速度与校验兼顾）";;
    after)  MODE_DESC="先快拷 + 拷完整盘哈希复校（最彻底，会多读一遍源盘）";;
    none)   MODE_DESC="仅快拷、不校验（不推荐）";;
    *) error "VERIFY_MODE 取值错误：$VERIFY_MODE（应为 inline/after/none）"; exit 1;;
esac
info "校验模式: ${CYAN}${VERIFY_MODE}${NC} — ${MODE_DESC}"

# --- 第 1 步：源文件夹 ---
if [ -n "$1" ] && [ -d "$1" ]; then
    SRC="$1"; info "源文件夹（来自参数）: $SRC"
else
    info "请在弹出的对话框中选择 [源文件夹]..."
    SRC=$(pick_folder "选择要拷贝的源文件夹（老硬盘上的文件夹）")
    [ -z "$SRC" ] && { error "未选择源文件夹，退出"; exit 1; }
fi
SRC="${SRC%/}"
echo ""; info "源文件夹: ${CYAN}$SRC${NC}"

# --- 第 2 步：目标文件夹 ---
info "请在弹出的对话框中选择 [目标文件夹]（新硬盘上的位置）..."
DEST=$(pick_folder "选择目标文件夹（新硬盘上要存放的位置）")
[ -z "$DEST" ] && { error "未选择目标文件夹，退出"; exit 1; }
DEST="${DEST%/}"
echo ""; info "目标文件夹: ${CYAN}$DEST${NC}"

if [ "$(cd "$SRC" && pwd)" = "$(cd "$DEST" && pwd)" ]; then
    error "源和目标是同一个文件夹！请重新选择"; exit 1
fi

# --- 排除规则（copy 和 check 共用）---
FILTERS=(
    --exclude ".DS_Store"
    --exclude "._*"
    --exclude ".Spotlight-V100/**"
    --exclude ".fseventsd/**"
    --exclude ".Trashes/**"
    --exclude ".TemporaryItems/**"
    --exclude ".DocumentRevisions-V100/**"
    --exclude ".apdisk"
    --exclude "Thumbs.db"
    --exclude "rclone_log_*.txt"
    --exclude "rclone_check_*.txt"
)

# --- 第 3 步：扫描 ---
echo ""; info "正在扫描源文件夹..."
FILE_COUNT=$(find "$SRC" -type f 2>/dev/null | wc -l | tr -d ' ')
DIR_COUNT=$(find "$SRC" -type d 2>/dev/null | wc -l | tr -d ' ')
TOTAL_SIZE_KB=$(du -sk "$SRC" 2>/dev/null | cut -f1)
echo ""
echo "  📁 文件夹数量: $DIR_COUNT"
echo "  📄 文件数量:   $FILE_COUNT"
echo "  💾 总大小:     $(format_size "$TOTAL_SIZE_KB")"

# --- 第 4 步：目标盘空间 ---
DEST_AVAIL_KB=$(df -k "$DEST" | tail -1 | awk '{print $4}')
echo ""; echo "  🗄️  目标盘剩余: $(format_size "$DEST_AVAIL_KB")"
if [ "$TOTAL_SIZE_KB" -gt "$DEST_AVAIL_KB" ]; then
    error "目标盘空间不足！需要 $(format_size "$TOTAL_SIZE_KB")，仅剩 $(format_size "$DEST_AVAIL_KB")"
    exit 1
fi

# --- 第 5 步：确认 ---
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  即将拷贝: ${CYAN}$(basename "$SRC")${NC}"
echo -e "  从: $SRC"
echo -e "  到: $DEST"
echo -e "  模式: $MODE_DESC"
echo -e "  并行: TRANSFERS=$TRANSFERS  CHECKERS=$CHECKERS  多路=$MULTI_STREAMS"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
read -p "确认开始拷贝？(y/n): " CONFIRM
[[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && { warn "用户取消操作"; exit 0; }

# --- 第 6 步：日志 ---
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SRC_NAME=$(basename "$SRC")
LOG_FILE="${DEST}/rclone_log_${SRC_NAME}_${TIMESTAMP}.txt"

# --- 第 7 步：拷贝 ---
echo ""; info "开始拷贝，请耐心等待..."; info "日志文件: $LOG_FILE"; echo ""
START_TIME=$(date +%s)

# none / after 模式跳过内嵌校验，让拷贝阶段全速顺序写入
COPY_EXTRA=()
if [ "$VERIFY_MODE" != "inline" ]; then
    COPY_EXTRA+=(--ignore-checksum)
fi

rclone copy "$SRC" "$DEST" \
    --transfers "$TRANSFERS" \
    --checkers "$CHECKERS" \
    --multi-thread-streams "$MULTI_STREAMS" \
    --multi-thread-cutoff "$MULTI_CUTOFF" \
    --progress --stats 1s --stats-one-line \
    --log-file "$LOG_FILE" --log-level INFO \
    "${COPY_EXTRA[@]}" "${FILTERS[@]}"
EXIT_CODE=$?

# --- after 模式：拷完整盘哈希复校 ---
CHECK_CODE=0
if [ "$VERIFY_MODE" = "after" ] && [ $EXIT_CODE -eq 0 ]; then
    echo ""; info "正在整盘哈希复校（--checksum --one-way，从物理盘片回读重算哈希）..."
    CHECK_LOG="${DEST}/rclone_check_${SRC_NAME}_${TIMESTAMP}.txt"
    rclone check "$SRC" "$DEST" \
        --checksum --one-way --checkers "$CHECKERS" \
        --log-file "$CHECK_LOG" --log-level INFO \
        "${FILTERS[@]}"
    CHECK_CODE=$?
fi

END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "  耗时: $(( ELAPSED / 60 )) 分 $(( ELAPSED % 60 )) 秒"

if [ $EXIT_CODE -ne 0 ]; then
    error "rclone 拷贝异常退出，退出码: $EXIT_CODE"; error "请检查日志: $LOG_FILE"
    grep -i "error\|fail\|corrupt\|ERROR" "$LOG_FILE" 2>/dev/null | head -20
    notify "拷贝异常 ❌ 退出码 $EXIT_CODE"
elif [ "$VERIFY_MODE" = "after" ] && [ $CHECK_CODE -ne 0 ]; then
    error "拷贝完成，但整盘复校发现差异！退出码: $CHECK_CODE"
    error "请检查复校日志: $CHECK_LOG"
    grep -i "error\|differ\|not in\|missing" "$CHECK_LOG" 2>/dev/null | head -20
    notify "复校发现差异 ❌ 请检查日志"
else
    case "$VERIFY_MODE" in
        inline) success "拷贝完成！每个文件写入后均已通过哈希校验";;
        after)  success "拷贝完成，且整盘哈希复校通过！源中所有文件在目标均一致";;
        none)   success "拷贝完成（未做校验）";;
    esac
    notify "拷贝完成 ✅ $FILE_COUNT 个文件，耗时 $(( ELAPSED / 60 ))分$(( ELAPSED % 60 ))秒"
fi
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# --- 第 8 步：抽样验证（内容级，验证文件能否正常打开）---
echo ""
read -p "是否进行抽样验证？随机检查30张图片+10个视频能否正常打开 (y/n): " DO_CHECK
if [[ "$DO_CHECK" == "y" || "$DO_CHECK" == "Y" ]]; then
    echo ""; info "抽样验证照片..."
    find "$DEST" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.heic" -o -iname "*.cr2" -o -iname "*.cr3" \) 2>/dev/null | \
        sort -R | head -30 | while read -r img; do
            if sips -g pixelWidth "$img" > /dev/null 2>&1; then echo -e "  ${GREEN}✅${NC} $(basename "$img")"
            else echo -e "  ${RED}❌${NC} $(basename "$img")"; fi
        done
    echo ""; info "抽样验证视频（如已安装 ffprobe）..."
    if command -v ffprobe &> /dev/null; then
        find "$DEST" -type f \( -iname "*.mp4" -o -iname "*.mov" -o -iname "*.mts" -o -iname "*.avi" \) 2>/dev/null | \
            sort -R | head -10 | while read -r vid; do
                if ffprobe -v error "$vid" > /dev/null 2>&1; then echo -e "  ${GREEN}✅${NC} $(basename "$vid")"
                else echo -e "  ${RED}❌${NC} $(basename "$vid")"; fi
            done
    else
        warn "ffprobe 未安装，跳过视频验证（可选安装: brew install ffmpeg）"
    fi
    echo ""; success "抽样验证完成"
fi

echo ""; info "拷贝日志: $LOG_FILE"; echo ""
read -p "按回车键关闭窗口..."
