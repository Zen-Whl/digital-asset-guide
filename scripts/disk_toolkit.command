#!/bin/bash
# ============================================================
# 磁盘管理工具集 v2.0
# Disk Management Toolkit
# 兼容 macOS 12 (Monterey) ~ macOS 15 (Sequoia)
#
# 与 generate_info.command 的分工:
#   generate_info   → 生成 DISK_INFO.md / FOLDER_INFO.md 文档
#   本工具集        → 执行具体的维护操作（去重、整理、健康检查等）
#
# 使用方式:
#   1. 双击运行（弹出菜单选择功能）
#   2. 命令行: ./disk_toolkit.command
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${BLUE}ℹ ${NC}$1"; }
success() { echo -e "${GREEN}✅ ${NC}$1"; }
warn()    { echo -e "${YELLOW}⚠️  ${NC}$1"; }
error()   { echo -e "${RED}❌ ${NC}$1"; }

pick_folder() {
    osascript -e "set f to choose folder with prompt \"$1\"
        return POSIX path of f" 2>/dev/null
}

format_size_kb() {
    local KB=$1
    if [ -z "$KB" ] || [ "$KB" -eq 0 ] 2>/dev/null; then echo "0 KB"; return; fi
    if [ "$KB" -ge 1073741824 ]; then echo "$(echo "scale=2; $KB/1073741824" | bc) TB"
    elif [ "$KB" -ge 1048576 ]; then echo "$(echo "scale=2; $KB/1048576" | bc) GB"
    elif [ "$KB" -ge 1024 ]; then echo "$(echo "scale=1; $KB/1024" | bc) MB"
    else echo "${KB} KB"; fi
}

# ============================================================
# 功能 1: 查找重复文件（同盘内去重）
# 依赖: fdupes (brew install fdupes)
# ============================================================
func_find_duplicates() {
    echo -e "\n${BOLD}━━━ 查找重复文件（同盘内） ━━━${NC}\n"
    
    if ! command -v fdupes &>/dev/null; then
        error "fdupes 未安装"
        echo "  安装方法: brew install fdupes"
        return 1
    fi
    
    info "请选择要扫描的文件夹（建议选择单个磁盘根目录）..."
    local TARGET=$(pick_folder "选择要查找重复文件的文件夹")
    [ -z "$TARGET" ] && return
    
    local OUTPUT="${TARGET}/duplicates_$(date +%Y%m%d).txt"
    
    warn "重要提醒: 只在同一块硬盘内部去重，不要跨盘去重！"
    warn "跨盘的重复实际上起到了备份作用。"
    echo ""
    info "正在扫描: $TARGET"
    info "大容量磁盘可能需要很长时间..."
    echo ""
    
    fdupes -r -S "$TARGET" > "$OUTPUT" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        local GROUPS=$(grep -c "^$" "$OUTPUT" 2>/dev/null || echo 0)
        local DUP_SIZE=$(grep -v "^$" "$OUTPUT" | while read -r f; do
            [ -f "$f" ] && du -sk "$f" 2>/dev/null
        done | awk '{s+=$1} END {print s+0}')
        local DUP_SIZE_FMT=$(format_size_kb "$DUP_SIZE")
        
        echo ""
        success "扫描完成"
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo "  重复文件组数: $GROUPS"
        echo "  重复文件占用: $DUP_SIZE_FMT"
        echo "  报告文件: $OUTPUT"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        warn "请先检查报告，确认后再手动删除！"
        echo "  交互式删除: fdupes -r -d \"$TARGET\""
        echo "  （会逐组询问保留哪个、删除哪个）"
    fi
}

# ============================================================
# 功能 2: 散落照片按日期整理
# 依赖: exiftool (brew install exiftool)
# ============================================================
func_organize_photos() {
    echo -e "\n${BOLD}━━━ 散落照片按拍摄日期整理 ━━━${NC}\n"
    
    if ! command -v exiftool &>/dev/null; then
        error "exiftool 未安装"
        echo "  安装方法: brew install exiftool"
        return 1
    fi
    
    warn "此功能仅用于未整理的散落照片！"
    warn "已按 YYYYMMDD-事件名 整理好的文件夹不要使用此功能。"
    echo ""
    
    info "请选择包含散落照片的 [源文件夹]..."
    local SRC=$(pick_folder "选择包含散落照片的源文件夹（如老硬盘的 DCIM 目录）")
    [ -z "$SRC" ] && return
    
    info "请选择整理后的 [目标文件夹]..."
    local DEST=$(pick_folder "选择目标文件夹（照片将按日期创建子文件夹存放于此）")
    [ -z "$DEST" ] && return
    
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "  源: $SRC"
    echo "  目标: $DEST"
    echo "  格式: YYYY/YYYYMMDD-Untitled/"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    read -p "确认开始整理？(y/n): " CONFIRM
    [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ] && return
    
    echo ""
    info "正在按拍摄日期整理..."
    echo ""
    
    # 优先使用 DateTimeOriginal，其次 CreateDate，最后 FileModifyDate
    exiftool -r \
        -d "${DEST}/%Y/%Y%m%d-Untitled/" \
        '-Directory<DateTimeOriginal' \
        '-Directory<CreateDate' \
        '-Directory<FileModifyDate' \
        "$SRC"
    
    echo ""
    success "整理完成"
    warn "请手动将 'Untitled' 重命名为实际事件名"
    echo "  例: 20240501-Untitled → 20240501-带小花逛弯"
}

# ============================================================
# 功能 3: SMART 健康检查
# 依赖: smartmontools (brew install smartmontools)
# ============================================================
func_smart_check() {
    echo -e "\n${BOLD}━━━ SMART 健康检查 ━━━${NC}\n"
    
    if ! command -v smartctl &>/dev/null; then
        error "smartmontools 未安装"
        echo "  安装方法: brew install smartmontools"
        return 1
    fi
    
    # 列出所有磁盘
    info "当前系统磁盘:"
    echo ""
    diskutil list | grep -E "^/dev/|external" | head -20
    echo ""
    
    read -p "请输入要检查的磁盘设备 (例: /dev/disk2): " DISK
    [ -z "$DISK" ] && return
    
    echo ""
    info "正在读取 SMART 数据（需要 sudo 权限）..."
    echo ""
    
    local OUTPUT="$HOME/Desktop/SMART_$(basename "$DISK")_$(date +%Y%m%d).txt"
    
    {
        echo "=== SMART Health Report ==="
        echo "设备: $DISK"
        echo "日期: $(date)"
        echo ""
        sudo smartctl -a "$DISK" 2>&1
    } | tee "$OUTPUT"
    
    echo ""
    
    # 检查关键指标
    local REALLOCATED=$(grep -i "Reallocated_Sector" "$OUTPUT" 2>/dev/null | awk '{print $NF}')
    local PENDING=$(grep -i "Current_Pending" "$OUTPUT" 2>/dev/null | awk '{print $NF}')
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    if [ -n "$REALLOCATED" ] && [ "$REALLOCATED" -gt 0 ] 2>/dev/null; then
        echo -e "  ${RED}⚠️  重新分配扇区: $REALLOCATED （异常！）${NC}"
        echo -e "  ${RED}  建议: 尽快迁移数据，此盘不应继续使用${NC}"
    elif [ -n "$REALLOCATED" ]; then
        echo -e "  ${GREEN}✅ 重新分配扇区: 0 （正常）${NC}"
    fi
    if [ -n "$PENDING" ] && [ "$PENDING" -gt 0 ] 2>/dev/null; then
        echo -e "  ${RED}⚠️  待处理扇区: $PENDING （异常！）${NC}"
    elif [ -n "$PENDING" ]; then
        echo -e "  ${GREEN}✅ 待处理扇区: 0 （正常）${NC}"
    fi
    echo "  📝 完整报告已保存: $OUTPUT"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ============================================================
# 功能 4: 年度照片/视频统计
# ============================================================
func_yearly_stats() {
    echo -e "\n${BOLD}━━━ 年度照片/视频统计 ━━━${NC}\n"
    
    info "请选择照片视频根目录（如 01_Photo-Video）..."
    local TARGET=$(pick_folder "选择照片视频根目录")
    [ -z "$TARGET" ] && return
    
    echo ""
    printf "${BOLD}%-6s %10s %10s %10s %12s${NC}\n" "年份" "照片" "视频" "RAW" "总大小"
    printf "%-6s %10s %10s %10s %12s\n" "------" "--------" "--------" "--------" "----------"
    
    TOTAL_P=0; TOTAL_V=0; TOTAL_R=0
    
    for year_dir in "$TARGET"/20*/; do
        [ ! -d "$year_dir" ] && continue
        local YEAR=$(basename "$year_dir")
        
        local PHOTOS=$(find "$year_dir" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.heic" \) 2>/dev/null | wc -l | tr -d ' ')
        local VIDEOS=$(find "$year_dir" -type f \( -iname "*.mp4" -o -iname "*.mov" -o -iname "*.avi" -o -iname "*.mkv" -o -iname "*.mts" \) 2>/dev/null | wc -l | tr -d ' ')
        local RAWS=$(find "$year_dir" -type f \( -iname "*.cr2" -o -iname "*.cr3" -o -iname "*.nef" -o -iname "*.arw" -o -iname "*.dng" -o -iname "*.raf" -o -iname "*.orf" \) 2>/dev/null | wc -l | tr -d ' ')
        local SIZE=$(du -sh "$year_dir" 2>/dev/null | cut -f1)
        
        TOTAL_P=$((TOTAL_P + PHOTOS))
        TOTAL_V=$((TOTAL_V + VIDEOS))
        TOTAL_R=$((TOTAL_R + RAWS))
        
        printf "%-6s %10s %10s %10s %12s\n" "$YEAR" "$PHOTOS" "$VIDEOS" "$RAWS" "$SIZE"
    done
    
    local TOTAL_SIZE=$(du -sh "$TARGET" 2>/dev/null | cut -f1)
    printf "%-6s %10s %10s %10s %12s\n" "------" "--------" "--------" "--------" "----------"
    printf "${BOLD}%-6s %10s %10s %10s %12s${NC}\n" "合计" "$TOTAL_P" "$TOTAL_V" "$TOTAL_R" "$TOTAL_SIZE"
}

# ============================================================
# 功能 5: 抽样验证照片/视频完整性
# ============================================================
func_spot_check() {
    echo -e "\n${BOLD}━━━ 抽样验证文件完整性 ━━━${NC}\n"
    
    info "请选择要验证的文件夹（如 rsync 拷贝的目标文件夹）..."
    local TARGET=$(pick_folder "选择要验证的文件夹")
    [ -z "$TARGET" ] && return
    
    local SAMPLE=30
    read -p "抽样数量 (默认 30): " INPUT_SAMPLE
    [ -n "$INPUT_SAMPLE" ] && SAMPLE=$INPUT_SAMPLE
    
    echo ""
    info "验证照片 (抽样 $SAMPLE 张)..."
    local PHOTO_OK=0; local PHOTO_FAIL=0
    
    find "$TARGET" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.heic" -o -iname "*.cr2" -o -iname "*.cr3" \) 2>/dev/null | \
        sort -R | head -n "$SAMPLE" | while read -r img; do
            if sips -g pixelWidth "$img" > /dev/null 2>&1; then
                echo -e "  ${GREEN}✅${NC} $(basename "$img")"
            else
                echo -e "  ${RED}❌ CORRUPTED${NC}: $img"
            fi
        done
    
    echo ""
    if command -v ffprobe &>/dev/null; then
        info "验证视频 (抽样 10 个)..."
        find "$TARGET" -type f \( -iname "*.mp4" -o -iname "*.mov" -o -iname "*.mts" -o -iname "*.avi" \) 2>/dev/null | \
            sort -R | head -10 | while read -r vid; do
                if ffprobe -v error "$vid" > /dev/null 2>&1; then
                    echo -e "  ${GREEN}✅${NC} $(basename "$vid")"
                else
                    echo -e "  ${RED}❌ CORRUPTED${NC}: $vid"
                fi
            done
    else
        warn "ffprobe 未安装，跳过视频验证 (可选: brew install ffmpeg)"
    fi
    
    echo ""
    success "抽样验证完成"
}

# ============================================================
# 主菜单
# ============================================================

show_menu() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════╗"
    echo "║   Disk Management Toolkit  v2.0              ║"
    echo "║   磁盘管理工具集                             ║"
    echo "╚══════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "  配套工具说明:"
    echo "  · generate_info.command  → 生成 DISK_INFO/FOLDER_INFO 文档"
    echo "  · smart_triage.command   → 桌面和下载文件夹智能分拣"
    echo "  · rsync_smart_copy.command → 老盘迁移拷贝"
    echo "  · rsync_mirror_sync.command → 大盘镜像同步"
    echo "  · 本工具集 → 以下维护操作"
    echo ""
    echo -e "  ${BOLD}[1]${NC} 查找重复文件（同盘内去重）        需要: fdupes"
    echo -e "  ${BOLD}[2]${NC} 散落照片按拍摄日期整理            需要: exiftool"
    echo -e "  ${BOLD}[3]${NC} SMART 硬盘健康检查                需要: smartmontools"
    echo -e "  ${BOLD}[4]${NC} 年度照片/视频统计                 无依赖"
    echo -e "  ${BOLD}[5]${NC} 抽样验证文件完整性                可选: ffmpeg"
    echo ""
    echo -e "  ${BOLD}[0]${NC} 退出"
    echo ""
    echo -e "  ${GRAY}依赖一键安装: brew install exiftool fdupes smartmontools ffmpeg${NC}"
    echo ""
}

while true; do
    show_menu
    read -p "  请选择功能 (0-5): " CHOICE
    
    case "$CHOICE" in
        1) func_find_duplicates ;;
        2) func_organize_photos ;;
        3) func_smart_check ;;
        4) func_yearly_stats ;;
        5) func_spot_check ;;
        0) echo ""; success "再见！"; exit 0 ;;
        *) warn "无效选项" ;;
    esac
    
    echo ""
    read -p "按回车键返回主菜单..."
done
