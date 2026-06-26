#!/bin/bash
# ============================================================
# 散乱文件智能分拣器 v1.0
# Smart File Triage — Desktop & Downloads Cleanup
# 兼容 macOS 12 (Monterey) ~ macOS 15 (Sequoia)
#
# 设计理念:
#   不是 Finder 的"按种类显示"——那只改变视图，不移动文件。
#   本脚本按数据管理指南的语义分类逻辑，将散乱文件实际移动
#   到分拣暂存区，便于人工快速判断最终归档位置。
#
# 核心逻辑:
#   1. 扫描指定文件夹（默认: 桌面 + 下载）
#   2. 按文件类型分拣到 _Triage/ 暂存文件夹
#   3. 暂存文件夹的分类对应指南中的顶级目录
#   4. 你快速过一遍暂存区，决定保留/归档/删除
#   5. 确认后一键移入正式归档位置
#
# 使用方式:
#   1. 双击运行（自动整理桌面和下载文件夹）
#   2. 右键文件夹 → Quick Action → 智能分拣
#   3. 命令行: ./smart_triage.command ~/Downloads
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${BLUE}ℹ ${NC}$1"; }
success() { echo -e "${GREEN}✅ ${NC}$1"; }
warn()    { echo -e "${YELLOW}⚠️  ${NC}$1"; }

pick_folder() {
    osascript -e "set f to choose folder with prompt \"$1\"
        return POSIX path of f" 2>/dev/null
}

clear
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════╗"
echo "║   Smart File Triage  v1.0                    ║"
echo "║   散乱文件智能分拣器                         ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${NC}"

# ============================================================
# 确定扫描源
# ============================================================
if [ -n "$1" ] && [ -d "$1" ]; then
    SOURCES=("$1")
    info "分拣目标: $1"
else
    # 默认扫描桌面和下载
    DESKTOP="$HOME/Desktop"
    DOWNLOADS="$HOME/Downloads"
    SOURCES=()
    
    echo "  请选择要分拣的文件夹:"
    echo ""
    echo "  [1] 桌面 ($DESKTOP)"
    echo "  [2] 下载 ($DOWNLOADS)"
    echo "  [3] 桌面 + 下载（同时整理）"
    echo "  [4] 选择其他文件夹"
    echo ""
    read -p "  请输入选项 (1/2/3/4): " CHOICE
    
    case "$CHOICE" in
        1) SOURCES=("$DESKTOP") ;;
        2) SOURCES=("$DOWNLOADS") ;;
        3) SOURCES=("$DESKTOP" "$DOWNLOADS") ;;
        4) CUSTOM=$(pick_folder "选择要分拣的文件夹")
           [ -z "$CUSTOM" ] && { echo "未选择，退出"; exit 1; }
           SOURCES=("$CUSTOM") ;;
        *) SOURCES=("$DESKTOP" "$DOWNLOADS") ;;
    esac
fi

echo ""

# ============================================================
# 创建分拣暂存区
# ============================================================
# 暂存区放在第一个源文件夹内，以 _Triage_日期 命名
TRIAGE_BASE="${SOURCES[0]}/_Triage_$(date +%Y%m%d)"

# 暂存分类文件夹 — 对应指南的顶级目录 + Q4 待删除
TRIAGE_PHOTO="$TRIAGE_BASE/01_照片视频_待归档"
TRIAGE_DOC="$TRIAGE_BASE/02_文档_待归档"
TRIAGE_SCREENSHOT="$TRIAGE_BASE/02_截屏_待分拣"
TRIAGE_MEDIA="$TRIAGE_BASE/04_影音资源_可删除"
TRIAGE_SOFTWARE="$TRIAGE_BASE/05_软件安装包_可删除"
TRIAGE_EBOOK="$TRIAGE_BASE/04_电子书_待归档"
TRIAGE_ARCHIVE="$TRIAGE_BASE/压缩包_待解压检查"
TRIAGE_OTHER="$TRIAGE_BASE/其他_待人工判断"
TRIAGE_TRASH="$TRIAGE_BASE/Q4_建议删除"

mkdir -p "$TRIAGE_PHOTO" "$TRIAGE_DOC" "$TRIAGE_SCREENSHOT" \
         "$TRIAGE_MEDIA" "$TRIAGE_SOFTWARE" "$TRIAGE_EBOOK" \
         "$TRIAGE_ARCHIVE" "$TRIAGE_OTHER" "$TRIAGE_TRASH"

info "暂存区: ${CYAN}$TRIAGE_BASE${NC}"
echo ""

# ============================================================
# 分拣规则
# ============================================================
classify_file() {
    local FILE="$1"
    local NAME=$(basename "$FILE")
    local EXT=$(echo "${NAME##*.}" | tr '[:upper:]' '[:lower:]')
    local SIZE_KB=$(du -sk "$FILE" 2>/dev/null | cut -f1)
    
    # --- 跳过隐藏文件和系统文件 ---
    [[ "$NAME" == .* ]] && return
    [[ "$NAME" == "Icon"$'\r' ]] && return
    
    # --- macOS 截屏文件（特征：以"截屏"或"Screenshot"开头的 .png）---
    if [[ "$EXT" == "png" && ("$NAME" == 截屏* || "$NAME" == "Screenshot"* || "$NAME" == 截图* || "$NAME" == "Screen Shot"*) ]]; then
        mv "$FILE" "$TRIAGE_SCREENSHOT/" 2>/dev/null
        return
    fi
    
    # --- 照片（相机文件，通常较大） ---
    case "$EXT" in
        cr2|cr3|nef|arw|orf|rw2|raf|dng|raw)
            mv "$FILE" "$TRIAGE_PHOTO/" 2>/dev/null; return ;;
    esac
    
    # --- 照片（JPEG/HEIC，区分相机照片和网图）---
    case "$EXT" in
        jpg|jpeg|heic|heif)
            # 相机照片通常 > 1MB，网上下载的图通常 < 500KB
            if [ "$SIZE_KB" -gt 1024 ]; then
                mv "$FILE" "$TRIAGE_PHOTO/" 2>/dev/null
            elif [[ "$NAME" == IMG_* || "$NAME" == DSC_* || "$NAME" == DJI_* || "$NAME" == DSCF* || "$NAME" == P10* ]]; then
                mv "$FILE" "$TRIAGE_PHOTO/" 2>/dev/null
            else
                mv "$FILE" "$TRIAGE_OTHER/" 2>/dev/null
            fi
            return ;;
    esac
    
    # --- 普通 PNG（非截屏的） ---
    case "$EXT" in
        png|gif|webp|bmp|tiff|tif|svg)
            mv "$FILE" "$TRIAGE_OTHER/" 2>/dev/null; return ;;
    esac
    
    # --- 视频 ---
    case "$EXT" in
        mp4|mov|avi|mkv|mts|m2ts|wmv|flv|mpg|mpeg|ts|m4v|3gp)
            # 相机视频通常 > 100MB
            if [ "$SIZE_KB" -gt 102400 ] || [[ "$NAME" == DJI_* || "$NAME" == MVI_* || "$NAME" == GH0* || "$NAME" == GOPR* ]]; then
                mv "$FILE" "$TRIAGE_PHOTO/" 2>/dev/null
            else
                mv "$FILE" "$TRIAGE_MEDIA/" 2>/dev/null
            fi
            return ;;
    esac
    
    # --- 音频 ---
    case "$EXT" in
        mp3|wav|flac|aac|m4a|ogg|wma|aiff)
            mv "$FILE" "$TRIAGE_MEDIA/" 2>/dev/null; return ;;
    esac
    
    # --- 文档 ---
    case "$EXT" in
        pdf|doc|docx|xls|xlsx|ppt|pptx|txt|md|rtf|csv|pages|numbers|keynote)
            mv "$FILE" "$TRIAGE_DOC/" 2>/dev/null; return ;;
    esac
    
    # --- 电子书 ---
    case "$EXT" in
        epub|mobi|azw|azw3|fb2)
            mv "$FILE" "$TRIAGE_EBOOK/" 2>/dev/null; return ;;
    esac
    
    # --- 软件安装包 ---
    case "$EXT" in
        dmg|pkg|app|exe|msi|deb|rpm)
            mv "$FILE" "$TRIAGE_SOFTWARE/" 2>/dev/null; return ;;
    esac
    
    # --- 压缩包（需人工查看内容再决定）---
    case "$EXT" in
        zip|rar|7z|tar|gz|bz2|xz|tgz)
            mv "$FILE" "$TRIAGE_ARCHIVE/" 2>/dev/null; return ;;
    esac
    
    # --- 临时/缓存文件（建议删除）---
    case "$EXT" in
        tmp|temp|cache|crdownload|part|download)
            mv "$FILE" "$TRIAGE_TRASH/" 2>/dev/null; return ;;
    esac
    
    # --- IPTV / 播放列表 ---
    case "$EXT" in
        m3u|m3u8|pls)
            mv "$FILE" "$TRIAGE_MEDIA/" 2>/dev/null; return ;;
    esac
    
    # --- 其他所有文件 ---
    mv "$FILE" "$TRIAGE_OTHER/" 2>/dev/null
}

# ============================================================
# 执行分拣
# ============================================================
TOTAL_MOVED=0

for SRC in "${SOURCES[@]}"; do
    info "扫描: ${BOLD}$(basename "$SRC")${NC}"
    
    # 只处理一级文件，不递归进入子文件夹（子文件夹可能是用户有意组织的）
    find "$SRC" -maxdepth 1 -type f ! -name ".*" 2>/dev/null | while read -r FILE; do
        FNAME=$(basename "$FILE")
        # 跳过分拣器自己生成的文件
        [[ "$FNAME" == "_Triage_"* ]] && continue
        
        classify_file "$FILE"
        TOTAL_MOVED=$((TOTAL_MOVED + 1))
        printf "\r  已分拣 %d 个文件..." "$TOTAL_MOVED"
    done
    echo ""
done

# ============================================================
# 统计结果
# ============================================================
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${BOLD}分拣完成！${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 统计每个暂存文件夹的文件数
show_count() {
    local DIR="$1"
    local LABEL="$2"
    local COLOR="$3"
    local COUNT=$(find "$DIR" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$COUNT" -gt 0 ]; then
        local SIZE=$(du -sh "$DIR" 2>/dev/null | cut -f1)
        echo -e "  ${COLOR}${LABEL}${NC}: ${BOLD}${COUNT}${NC} 个文件 ($SIZE)"
    fi
}

show_count "$TRIAGE_PHOTO"      "📷 照片视频 → 01_Photo-Video" "$GREEN"
show_count "$TRIAGE_DOC"        "📄 文档     → 02_Documents"   "$GREEN"
show_count "$TRIAGE_SCREENSHOT" "🖥️  截屏     → 需人工三类分拣" "$YELLOW"
show_count "$TRIAGE_EBOOK"      "📚 电子书   → 04_Media"       "$BLUE"
show_count "$TRIAGE_MEDIA"      "🎬 影音资源 → 04_Media 或删除" "$BLUE"
show_count "$TRIAGE_SOFTWARE"   "💿 安装包   → 05_Software 或删除" "$BLUE"
show_count "$TRIAGE_ARCHIVE"    "📦 压缩包   → 需解压检查内容" "$YELLOW"
show_count "$TRIAGE_OTHER"      "❓ 其他     → 需人工判断"     "$YELLOW"
show_count "$TRIAGE_TRASH"      "🗑️  建议删除 → 临时/缓存文件" "$RED"

echo ""

# ============================================================
# 清理空文件夹
# ============================================================
for DIR in "$TRIAGE_PHOTO" "$TRIAGE_DOC" "$TRIAGE_SCREENSHOT" \
           "$TRIAGE_MEDIA" "$TRIAGE_SOFTWARE" "$TRIAGE_EBOOK" \
           "$TRIAGE_ARCHIVE" "$TRIAGE_OTHER" "$TRIAGE_TRASH"; do
    COUNT=$(find "$DIR" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
    [ "$COUNT" -eq 0 ] && rmdir "$DIR" 2>/dev/null
done

# ============================================================
# 生成分拣说明
# ============================================================
cat > "$TRIAGE_BASE/README_分拣说明.md" << 'EOF'
# 分拣暂存区说明

本文件夹由"散乱文件智能分拣器"自动生成，按数据管理指南的分类逻辑
将桌面和下载文件夹中的散乱文件移入对应的暂存文件夹。

## 下一步操作

### 01_照片视频_待归档
→ 移入 01_Photo-Video/ 对应年份和事件文件夹
→ 如需按拍摄日期自动创建文件夹：exiftool -d "%Y/%Y%m%d-Untitled/" '-Directory<DateTimeOriginal' *.CR3

### 02_文档_待归档
→ 按内容判断归入 02_Documents/ 的哪个子目录（Finance/Identity/Work 等）
→ 重命名为 YYYYMMDD-描述.ext 格式

### 02_截屏_待分拣（需人工三类判断）
→ 凭证类（转账、合同、理赔）→ 02_Documents/ 对应领域，重命名
→ 事件相关（酒店确认、项目参考）→ 对应事件或项目文件夹
→ 其余全部 → 删除，或移入 Q4_建议删除 等3个月

### 04_影音资源_可删除 / 04_电子书_待归档
→ 想保留的移入 04_Media/
→ 不需要的直接删除

### 05_软件安装包_可删除
→ 常用的、将来可能重装的 → 05_Software/
→ 已安装且官网可重新下载的 → 删除

### 压缩包_待解压检查
→ 解压查看内容后按内容归档

### Q4_建议删除
→ 临时文件、缓存、下载中断的残留。确认后直接删除。

### 其他_待人工判断
→ 无法自动分类的文件，逐一检查归档或删除。

## 完成后
确认所有文件都已归档后，删除整个 _Triage_YYYYMMDD 文件夹。
EOF

success "分拣说明已写入: $TRIAGE_BASE/README_分拣说明.md"
echo ""

# --- 打开暂存区 ---
read -p "是否在 Finder 中打开暂存区？(y/n): " OPEN_TRIAGE
if [[ "$OPEN_TRIAGE" == "y" || "$OPEN_TRIAGE" == "Y" ]]; then
    open "$TRIAGE_BASE"
fi

# --- macOS 通知 ---
osascript -e "display notification \"散乱文件已分拣到暂存区，请检查后归档\" with title \"Smart Triage 完成\" sound name \"Glass\"" 2>/dev/null

echo ""
read -p "按回车键关闭窗口..."
