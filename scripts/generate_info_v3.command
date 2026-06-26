#!/bin/bash
# ============================================================
# 磁盘/文件夹信息文档自动生成器 v2.0
# Disk & Folder Info Generator
# 兼容 macOS 12 (Monterey) ~ macOS 15 (Sequoia)
#
# 综合优点来源：
#   - generate_disk_info.command: 磁盘级检测、象限标注、文件类型说明
#   - generate_inventory.py:     汇总表 + 详细目录树两遍扫描结构
#   - generate_readme.sh:        轻量、每项带大小、即扫即生成
#
# 使用方式:
#   1. 右键文件夹 → Quick Action → 生成信息文档
#   2. 双击本 .command 文件运行
#   3. 命令行: ./generate_info.command /Volumes/WD12TB-A
#   4. 命令行: ./generate_info.command /Volumes/WD12TB-A/01_Photo-Video/2024
#
# 输出:
#   磁盘根目录 → DISK_INFO.md（含磁盘硬件信息、备份策略提示）
#   普通文件夹 → FOLDER_INFO.md（含路径、上级关系）
# ============================================================

# === 颜色 ===
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${BLUE}ℹ ${NC}$1"; }
success() { echo -e "${GREEN}✅ ${NC}$1"; }
warn()    { echo -e "${YELLOW}⚠️  ${NC}$1"; }
progress(){ printf "\r${BLUE}  ⏳ ${NC}%-50s" "$1"; }

# === 系统过滤名单（综合自 generate_inventory.py）===
IGNORE_NAMES=".DS_Store|.localsite|System Volume Information|\$RECYCLE.BIN|.Trash|.Trashes|.Spotlight-V100|.fseventsd|.TemporaryItems|Thumbs.db"

# === 选择文件夹（macOS 原生对话框）===
pick_folder() {
    osascript -e "
        set f to choose folder with prompt \"$1\"
        return POSIX path of f
    " 2>/dev/null
}

# === 格式化大小（输入 KB）===
format_size_kb() {
    local KB=$1
    if [ -z "$KB" ] || [ "$KB" -eq 0 ] 2>/dev/null; then echo "0 KB"; return; fi
    if [ "$KB" -ge 1073741824 ]; then echo "$(echo "scale=2; $KB/1073741824" | bc) TB"
    elif [ "$KB" -ge 1048576 ]; then echo "$(echo "scale=2; $KB/1048576" | bc) GB"
    elif [ "$KB" -ge 1024 ]; then echo "$(echo "scale=1; $KB/1024" | bc) MB"
    else echo "${KB} KB"; fi
}

# === 格式化大小（输入 Bytes，来自 generate_inventory.py 的逻辑）===
format_size_bytes() {
    local B=$1
    if [ -z "$B" ] || [ "$B" -eq 0 ] 2>/dev/null; then echo "0 B"; return; fi
    if [ "$B" -ge 1099511627776 ]; then echo "$(echo "scale=2; $B/1099511627776" | bc) TB"
    elif [ "$B" -ge 1073741824 ]; then echo "$(echo "scale=2; $B/1073741824" | bc) GB"
    elif [ "$B" -ge 1048576 ]; then echo "$(echo "scale=1; $B/1048576" | bc) MB"
    elif [ "$B" -ge 1024 ]; then echo "$(echo "scale=1; $B/1024" | bc) KB"
    else echo "${B} B"; fi
}

# === 获取文件夹创建日期（macOS BSD stat）===
get_created() { stat -f "%SB" -t "%Y-%m-%d" "$1" 2>/dev/null || echo "—"; }

# === 获取文件夹最后修改日期 ===
get_modified() { stat -f "%Sm" -t "%Y-%m-%d" "$1" 2>/dev/null || echo "—"; }

# === 文件类型说明（综合自 generate_disk_info.command，扩充条目）===
get_ext_desc() {
    case "$1" in
        jpg|jpeg) echo "JPEG 照片" ;; png) echo "PNG 图片" ;; gif) echo "GIF 动图" ;;
        heic|heif) echo "Apple HEIC" ;; webp) echo "WebP 图片" ;; tiff|tif) echo "TIFF 图片" ;;
        bmp) echo "BMP 位图" ;; svg) echo "SVG 矢量图" ;;
        cr2|cr3) echo "Canon RAW" ;; nef) echo "Nikon RAW" ;; arw) echo "Sony RAW" ;;
        orf) echo "Olympus RAW" ;; rw2) echo "Panasonic RAW" ;; raf) echo "Fuji RAW" ;;
        dng) echo "Adobe DNG" ;; raw) echo "通用 RAW" ;;
        mp4) echo "MP4 视频" ;; mov) echo "QuickTime 视频" ;; avi) echo "AVI 视频" ;;
        mkv) echo "MKV 视频" ;; mts|m2ts) echo "AVCHD 视频" ;; wmv) echo "WMV 视频" ;;
        flv) echo "FLV 视频" ;; mpg|mpeg) echo "MPEG 视频" ;; ts) echo "TS 视频流" ;;
        mp3) echo "MP3 音频" ;; wav) echo "WAV 音频" ;; flac) echo "FLAC 无损" ;;
        aac) echo "AAC 音频" ;; m4a) echo "M4A 音频" ;; ogg) echo "OGG 音频" ;;
        pdf) echo "PDF 文档" ;; doc) echo "Word 97-03" ;; docx) echo "Word 文档" ;;
        xls) echo "Excel 97-03" ;; xlsx) echo "Excel 表格" ;; ppt) echo "PPT 97-03" ;;
        pptx) echo "PPT 演示" ;; txt) echo "纯文本" ;; md) echo "Markdown" ;;
        csv) echo "CSV 数据" ;; json) echo "JSON 数据" ;; xml) echo "XML 数据" ;;
        html|htm) echo "网页文件" ;; rtf) echo "富文本" ;;
        psd) echo "Photoshop" ;; ai) echo "Illustrator" ;; indd) echo "InDesign" ;;
        prproj) echo "Premiere 工程" ;; aep) echo "After Effects" ;; fcpbundle) echo "FCPX 工程" ;;
        lrcat) echo "Lightroom 目录" ;; xmp) echo "XMP 元数据" ;;
        zip) echo "ZIP 压缩" ;; rar) echo "RAR 压缩" ;; 7z) echo "7z 压缩" ;;
        gz|tar) echo "归档压缩" ;; dmg) echo "macOS 磁盘映像" ;; iso) echo "光盘镜像" ;;
        app) echo "macOS 应用" ;; exe) echo "Windows 程序" ;; pkg) echo "安装包" ;;
        epub) echo "EPUB 电子书" ;; mobi|azw3) echo "Kindle 电子书" ;;
        srt|ass) echo "字幕文件" ;; lut|cube) echo "LUT 调色" ;;
        *) echo "" ;;
    esac
}

# ============================================================
# 主流程
# ============================================================

clear
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════╗"
echo "║   Disk & Folder Info Generator  v2.0         ║"
echo "║   磁盘 / 文件夹信息文档自动生成器            ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${NC}"

# --- 确定目标路径 ---
if [ -n "$1" ] && [ -d "$1" ]; then
    TARGET="$1"
else
    info "请在弹出的对话框中选择要分析的文件夹或磁盘根目录..."
    TARGET=$(pick_folder "选择要生成信息文档的文件夹或磁盘根目录")
    [ -z "$TARGET" ] && { echo "未选择文件夹，退出"; exit 1; }
fi
[[ "$TARGET" != */ ]] && TARGET="${TARGET}/"

# --- 判断磁盘根目录 vs 普通文件夹 ---
IS_VOLUME=false
VOLUME_MOUNT=$(df "$TARGET" 2>/dev/null | tail -1 | awk '{$1=$2=$3=$4=$5=""; print $0}' | xargs)
TARGET_REAL=$(cd "$TARGET" 2>/dev/null && pwd)
if [ "$TARGET_REAL" = "$VOLUME_MOUNT" ]; then
    IS_VOLUME=true
fi

FOLDER_NAME=$(basename "${TARGET%/}")
TODAY=$(date +%Y-%m-%d)
NOW=$(date "+%Y-%m-%d %H:%M:%S")

if $IS_VOLUME; then
    OUTPUT="${TARGET}DISK_INFO.md"
    info "检测类型: ${BOLD}磁盘根目录${NC}  →  DISK_INFO.md"
else
    OUTPUT="${TARGET}FOLDER_INFO.md"
    info "检测类型: ${BOLD}普通文件夹${NC}  →  FOLDER_INFO.md"
fi
info "目标路径: ${CYAN}${TARGET}${NC}"
echo ""
info "正在扫描，大容量磁盘可能需要数分钟..."
START_SEC=$(date +%s)

# ============================================================
# 第一遍扫描：收集全局数据
# ============================================================

progress "统计文件总数..."
TOTAL_FILES=$(find "$TARGET" -type f ! -name ".*" 2>/dev/null | grep -v -E "$IGNORE_NAMES" | wc -l | tr -d ' ')
TOTAL_DIRS=$(find "$TARGET" -type d ! -name ".*" 2>/dev/null | grep -v -E "$IGNORE_NAMES" | wc -l | tr -d ' ')
progress "计算总大小..."
TOTAL_SIZE_KB=$(du -sk "$TARGET" 2>/dev/null | cut -f1)
TOTAL_SIZE=$(format_size_kb "$TOTAL_SIZE_KB")

# --- 磁盘级信息 ---
if $IS_VOLUME; then
    progress "读取磁盘硬件信息..."
    DISK_DEVICE=$(df "$TARGET" 2>/dev/null | tail -1 | awk '{print $1}')
    DISK_FS=$(diskutil info "$TARGET" 2>/dev/null | grep -E "Type \(Bundle\)|File System Personality" | head -1 | awk -F: '{print $2}' | xargs)
    DISK_CAPACITY_KB=$(df -k "$TARGET" 2>/dev/null | tail -1 | awk '{print $2}')
    DISK_USED_KB=$(df -k "$TARGET" 2>/dev/null | tail -1 | awk '{print $3}')
    DISK_AVAIL_KB=$(df -k "$TARGET" 2>/dev/null | tail -1 | awk '{print $4}')
    DISK_CAPACITY=$(format_size_kb "$DISK_CAPACITY_KB")
    DISK_USED=$(format_size_kb "$DISK_USED_KB")
    DISK_AVAIL=$(format_size_kb "$DISK_AVAIL_KB")
    DISK_PERCENT="0%"
    [ "$DISK_CAPACITY_KB" -gt 0 ] 2>/dev/null && DISK_PERCENT=$(echo "scale=1; $DISK_USED_KB * 100 / $DISK_CAPACITY_KB" | bc)%
fi

# ============================================================
# 开始写入 Markdown
# ============================================================

{

# === 标题与基本信息 ===
if $IS_VOLUME; then
    echo "# DISK_INFO — $FOLDER_NAME"
else
    echo "# FOLDER_INFO — $FOLDER_NAME"
fi
echo ""
echo "> 本文件由自动化脚本生成，用于快速索引和管理数据内容。"
echo ""
echo "## 一、基本信息"
echo ""
if $IS_VOLUME; then
    echo "- **磁盘标签**: $FOLDER_NAME"
    echo "- **品牌/型号**: （请手动填写，例: WD Black WD121KRYZ）"
    echo "- **序列号**: （请手动填写）"
    echo "- **设备节点**: $DISK_DEVICE"
    echo "- **文件系统**: $DISK_FS"
    echo "- **总容量**: $DISK_CAPACITY"
    echo "- **已用空间**: $DISK_USED ($DISK_PERCENT)"
    echo "- **可用空间**: $DISK_AVAIL"
else
    echo "- **文件夹名**: $FOLDER_NAME"
    echo "- **完整路径**: $TARGET_REAL"
    echo "- **所在磁盘**: $VOLUME_MOUNT"
fi
echo "- **总文件数**: $TOTAL_FILES"
echo "- **总文件夹数**: $TOTAL_DIRS"
echo "- **总大小**: $TOTAL_SIZE"
echo "- **文档生成时间**: $NOW"
echo ""

# === 用途与备份策略（磁盘级别）===
if $IS_VOLUME; then
    echo "## 二、用途与备份策略（请手动填写）"
    echo ""
    echo "- **主要用途**: （例: 照片视频主存储 / 文档归档 / 媒体库 / 冷备份）"
    echo "- **四象限分类**: （Q1 不可替代+高频 / Q2 不可替代+低频 / Q3 可替代+高频）"
    echo "- **存储层级**: （Tier 1 活跃层 / Tier 2 镜像层 / Tier 3 冷备份）"
    echo "- **是否有备份副本**: 是 → 备份在 [磁盘标签]  /  否 ⚠️"
    echo "- **备份策略**: （例: 与 WD12TB-B 互为镜像，每月 rsync 同步）"
    echo "- **SMART 状态**: （正常 / 注意 — 最后检测日期: ）"
    echo "- **通电时长**: （例: 约 xxxx 小时）"
    echo ""
fi

# ============================================================
# 第二遍扫描：子文件夹汇总表（来自 inventory.py 的两遍扫描思路）
# ============================================================

SECTION_NUM=3
$IS_VOLUME && SECTION_NUM=3 || SECTION_NUM=2

echo "## ${SECTION_NUM_MAP:=$( $IS_VOLUME && echo "三" || echo "二" )}、存储概览"
echo ""
echo "| 子文件夹 | 大小 | 文件数 | 子文件夹数 | 创建日期 | 最后修改 |"
echo "|----------|------|--------|------------|----------|----------|"

SUB_COUNT=0
for dir in "$TARGET"*/; do
    [ ! -d "$dir" ] && continue
    DNAME=$(basename "$dir")
    [[ "$DNAME" == .* ]] && continue

    SUB_COUNT=$((SUB_COUNT + 1))
    progress "扫描: $DNAME ..."
    
    DSIZE_KB=$(du -sk "$dir" 2>/dev/null | cut -f1)
    DSIZE=$(format_size_kb "$DSIZE_KB")
    DFILES=$(find "$dir" -type f ! -name ".*" 2>/dev/null | grep -v -E "$IGNORE_NAMES" | wc -l | tr -d ' ')
    DDIRS=$(find "$dir" -type d ! -name ".*" 2>/dev/null | grep -v -E "$IGNORE_NAMES" | wc -l | tr -d ' ')
    DDIRS=$((DDIRS - 1))  # 减去自身
    [ "$DDIRS" -lt 0 ] && DDIRS=0
    DCREATED=$(get_created "$dir")
    DMODIFIED=$(get_modified "$dir")
    
    echo "| $DNAME | $DSIZE | $DFILES | $DDIRS | $DCREATED | $DMODIFIED |"
done

# 根目录散落文件
ROOT_LOOSE=$(find "$TARGET" -maxdepth 1 -type f ! -name ".*" ! -name "DISK_INFO.md" ! -name "FOLDER_INFO.md" ! -name "inventory*" ! -name "readme.txt" 2>/dev/null)
ROOT_LOOSE_COUNT=$(echo "$ROOT_LOOSE" | grep -c "." 2>/dev/null || echo 0)
if [ "$ROOT_LOOSE_COUNT" -gt 0 ] && [ -n "$ROOT_LOOSE" ]; then
    ROOT_LOOSE_KB=$(echo "$ROOT_LOOSE" | xargs du -sk 2>/dev/null | awk '{s+=$1} END {print s+0}')
    ROOT_LOOSE_SIZE=$(format_size_kb "$ROOT_LOOSE_KB")
    echo "| _(根目录散落文件)_ | $ROOT_LOOSE_SIZE | $ROOT_LOOSE_COUNT | — | — | — |"
fi

echo ""

# ============================================================
# 详细目录树（来自 inventory.py 的详细列表 + readme.sh 的带大小显示）
# ============================================================

SECTION_NEXT=$(( $IS_VOLUME ? 4 : 3 ))
echo "## $( [ $SECTION_NEXT -eq 4 ] && echo "四" || echo "三" )、详细目录树"
echo ""
echo "> 展开到二级子目录，每项标注文件数。"
echo ""

for dir in "$TARGET"*/; do
    [ ! -d "$dir" ] && continue
    DNAME=$(basename "$dir")
    [[ "$DNAME" == .* ]] && continue
    
    progress "展开: $DNAME ..."
    DSIZE=$(du -sh "$dir" 2>/dev/null | cut -f1)
    echo "### 📂 $DNAME ($DSIZE)"
    echo ""
    
    # 列出该目录下的二级子目录（来自 inventory.py 的逻辑）
    HAS_SUBS=false
    for sub in "$dir"*/; do
        [ ! -d "$sub" ] && continue
        SNAME=$(basename "$sub")
        [[ "$SNAME" == .* ]] && continue
        HAS_SUBS=true
        
        SFILES=$(find "$sub" -type f ! -name ".*" 2>/dev/null | grep -v -E "$IGNORE_NAMES" | wc -l | tr -d ' ')
        SSIZE=$(du -sh "$sub" 2>/dev/null | cut -f1)
        echo "- **$SNAME** — $SSIZE, $SFILES files"
    done
    
    # 如果没有子目录，列出文件（来自 readme.sh 的逻辑）
    if ! $HAS_SUBS; then
        FILE_LIST=$(find "$dir" -maxdepth 1 -type f ! -name ".*" 2>/dev/null | sort)
        if [ -n "$FILE_LIST" ]; then
            echo "$FILE_LIST" | while read -r fpath; do
                FNAME=$(basename "$fpath")
                FSIZE=$(du -sh "$fpath" 2>/dev/null | cut -f1)
                echo "- $FNAME ($FSIZE)"
            done
        else
            echo "*(空目录)*"
        fi
    fi
    echo ""
done

# ============================================================
# 文件类型分布（来自 generate_disk_info.command，扩充了格式说明）
# ============================================================

SECTION_NEXT2=$(( $IS_VOLUME ? 5 : 4 ))
echo "## $( [ $SECTION_NEXT2 -eq 5 ] && echo "五" || echo "四" )、文件类型分布"
echo ""
echo "| 排名 | 扩展名 | 文件数 | 说明 |"
echo "|------|--------|--------|------|"

progress "统计文件类型..."
RANK=0
find "$TARGET" -type f ! -name ".*" 2>/dev/null | grep -v -E "$IGNORE_NAMES" | \
    sed 's/.*\.//' | tr '[:upper:]' '[:lower:]' | sort | uniq -c | sort -rn | head -20 | \
    while read COUNT EXT; do
        RANK=$((RANK + 1))
        DESC=$(get_ext_desc "$EXT")
        echo "| $RANK | .$EXT | $COUNT | $DESC |"
    done

echo ""

# ============================================================
# 重要内容标记
# ============================================================

SECTION_NEXT3=$(( $IS_VOLUME ? 6 : 5 ))
echo "## $( [ $SECTION_NEXT3 -eq 6 ] && echo "六" || echo "五" )、⭐ 重要内容标记（请手动填写）"
echo ""
echo "<!-- 列出最重要的、不可替代的内容位置 -->"
echo "- ⭐ （例: 2008 汶川地震现场影像: /01_Photo-Video/2008/20080512-汶川地震-[Documentary]/）"
echo "- ⭐ （例: 2018 婚礼原始 RAW: /01_Photo-Video/2018/20180815-Wedding/）"
echo "- ⭐ （例: 2016 ClientA 项目原始素材: /06_Projects/Archive/2016/20160301-ClientA-TVC/_Source/）"
echo ""

# ============================================================
# 整理状态（磁盘级别）
# ============================================================

if $IS_VOLUME; then
    echo "## 七、整理状态（请手动更新）"
    echo ""
    echo "- **整理进度**: ❌ 待整理 / 🔄 进行中 / ✅ 已完成"
    echo "- **去重状态**: 待去重 / 已完成 (fdupes)"
    echo "- **数据来源**: （例: 从 Seagate-3TB-2015 迁入）"
    echo ""
fi

# ============================================================
# 变更记录
# ============================================================

SECTION_LOG=$( $IS_VOLUME && echo "八" || echo "六" )
echo "## ${SECTION_LOG}、变更记录"
echo ""
echo "| 日期 | 操作 |"
echo "|------|------|"
echo "| $TODAY | 信息文档自动生成 |"
echo "| | |"
echo ""

# ============================================================
# 页脚
# ============================================================

# 计算扫描耗时
END_SEC=$(date +%s)
ELAPSED=$(( END_SEC - START_SEC ))
ELAPSED_MIN=$(( ELAPSED / 60 ))
ELAPSED_SEC_R=$(( ELAPSED % 60 ))

echo "---"
echo ""
echo "**文档生成日期**: $NOW"
echo "**最后更新日期**: $NOW"
echo "**扫描耗时**: ${ELAPSED_MIN}分${ELAPSED_SEC_R}秒"
echo ""
echo "_由 generate_info.command v2.0 自动生成。手动标注项（品牌型号、备份策略、重要内容等）请自行补充。_"

} > "$OUTPUT"

# 清除进度行
printf "\r%-60s\r" ""

# ============================================================
# 终端摘要
# ============================================================

END_SEC=$(date +%s)
ELAPSED=$(( END_SEC - START_SEC ))

echo ""
success "文档已生成！"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  📁 ${BOLD}$FOLDER_NAME${NC}"
if $IS_VOLUME; then
    echo "  💾 $DISK_USED / $DISK_CAPACITY ($DISK_PERCENT)"
fi
echo "  📄 $TOTAL_FILES 个文件, $TOTAL_DIRS 个文件夹, $SUB_COUNT 个一级子目录"
echo "  📊 总大小: $TOTAL_SIZE"
echo "  ⏱️  扫描耗时: ${ELAPSED}秒"
echo "  📝 输出: $OUTPUT"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# --- macOS 通知 ---
osascript -e "display notification \"$FOLDER_NAME — $TOTAL_FILES 文件, $TOTAL_SIZE\" with title \"信息文档已生成\" sound name \"Glass\"" 2>/dev/null

# --- 是否打开 ---
read -p "是否用默认编辑器打开文档？(y/n): " OPEN_FILE
if [[ "$OPEN_FILE" == "y" || "$OPEN_FILE" == "Y" ]]; then
    open "$OUTPUT"
fi

echo ""
read -p "按回车键关闭窗口..."
