#!/bin/bash
# ============================================================
# 磁盘管理工具集 — Disk Management Toolkit
# 适用于 macOS / Linux
# ============================================================

# ============================================================
# 1. 生成目录清单（inventory）
#    用途：快速了解一块硬盘里有什么
# ============================================================
generate_inventory() {
    local DISK_PATH="${1:-.}"
    local OUTPUT="${DISK_PATH}/inventory_$(date +%Y%m%d).txt"

    echo "=== Disk Inventory ===" > "$OUTPUT"
    echo "Generated: $(date)" >> "$OUTPUT"
    echo "Path: $(cd "$DISK_PATH" && pwd)" >> "$OUTPUT"
    echo "" >> "$OUTPUT"

    # 磁盘使用概况
    echo "--- Disk Usage Summary ---" >> "$OUTPUT"
    du -sh "$DISK_PATH" 2>/dev/null >> "$OUTPUT"
    echo "" >> "$OUTPUT"

    # 顶级目录大小
    echo "--- Top-Level Directories ---" >> "$OUTPUT"
    du -sh "$DISK_PATH"/*/ 2>/dev/null | sort -rh >> "$OUTPUT"
    echo "" >> "$OUTPUT"

    # 文件类型统计
    echo "--- File Type Statistics ---" >> "$OUTPUT"
    find "$DISK_PATH" -type f | \
        sed 's/.*\.//' | sort | uniq -c | sort -rn | head -30 >> "$OUTPUT"
    echo "" >> "$OUTPUT"

    # 二级目录树
    echo "--- Directory Tree (2 levels) ---" >> "$OUTPUT"
    find "$DISK_PATH" -maxdepth 2 -type d | \
        sed "s|${DISK_PATH}||" | sort >> "$OUTPUT"

    echo "✅ Inventory saved to: $OUTPUT"
}

# 使用方法: generate_inventory /Volumes/WD12TB-A


# ============================================================
# 2. 查找重复文件
#    依赖: fdupes (macOS: brew install fdupes)
# ============================================================
find_duplicates() {
    local DISK_PATH="${1:-.}"
    local OUTPUT="${DISK_PATH}/duplicates_$(date +%Y%m%d).txt"

    echo "Scanning for duplicates in: $DISK_PATH"
    echo "This may take a long time for large disks..."

    # fdupes 按 MD5 查找重复文件
    fdupes -r -S "$DISK_PATH" > "$OUTPUT" 2>/dev/null

    if [ $? -eq 0 ]; then
        local DUP_COUNT=$(grep -c "^$" "$OUTPUT")
        echo "✅ Found $DUP_COUNT groups of duplicates"
        echo "   Report: $OUTPUT"
        echo "   Review before deleting! Use: fdupes -r -d $DISK_PATH (interactive delete)"
    else
        echo "❌ fdupes not found. Install: brew install fdupes"
    fi
}

# 使用方法: find_duplicates /Volumes/WD12TB-A


# ============================================================
# 3. 照片/视频按日期整理到 YYYY/YYYYMMDD-Untitled/ 结构
#    依赖: exiftool (macOS: brew install exiftool)
# ============================================================
organize_by_date() {
    local SRC_DIR="$1"
    local DEST_DIR="$2"

    if [ -z "$SRC_DIR" ] || [ -z "$DEST_DIR" ]; then
        echo "Usage: organize_by_date <source_dir> <destination_dir>"
        return 1
    fi

    echo "Organizing photos/videos from: $SRC_DIR"
    echo "Destination: $DEST_DIR"
    echo ""

    # 使用 exiftool 按拍摄日期移动文件
    # 格式: DEST/YYYY/YYYYMMDD-Untitled/filename.ext
    exiftool -r \
        -d "${DEST_DIR}/%Y/%Y%m%d-Untitled/" \
        '-Directory<DateTimeOriginal' \
        '-Directory<CreateDate' \
        '-Directory<FileModifyDate' \
        "$SRC_DIR"

    echo ""
    echo "✅ Done. Please review and rename 'Untitled' folders with event names."
}

# 使用方法: organize_by_date /Volumes/OldDisk/DCIM /Volumes/WD12TB-A/Photos


# ============================================================
# 4. SMART 健康检查
#    依赖: smartctl (macOS: brew install smartmontools)
# ============================================================
check_disk_health() {
    local DISK="${1:-/dev/disk0}"

    echo "=== SMART Health Report ==="
    echo "Disk: $DISK"
    echo "Date: $(date)"
    echo ""

    # 需要 sudo 权限
    sudo smartctl -a "$DISK" 2>/dev/null

    if [ $? -ne 0 ]; then
        echo "❌ smartctl not found or no permission."
        echo "   Install: brew install smartmontools"
        echo "   Run with: sudo check_disk_health /dev/diskN"
    fi
}


# ============================================================
# 5. 同步/镜像两块硬盘（用于备份）
#    使用 rsync，支持增量同步
# ============================================================
mirror_disks() {
    local SRC="$1"
    local DEST="$2"

    if [ -z "$SRC" ] || [ -z "$DEST" ]; then
        echo "Usage: mirror_disks <source_path> <destination_path>"
        echo "Example: mirror_disks /Volumes/WD12TB-A /Volumes/WD12TB-B"
        return 1
    fi

    echo "=== Disk Mirror ==="
    echo "Source:      $SRC"
    echo "Destination: $DEST"
    echo ""
    echo "⚠️  DRY RUN first (no changes)..."
    echo ""

    # 先做 dry-run 预览
    rsync -avhn --delete \
        --exclude=".Spotlight-*" \
        --exclude=".fseventsd" \
        --exclude=".Trashes" \
        --exclude=".DS_Store" \
        "$SRC/" "$DEST/"

    echo ""
    echo "👆 Above is the DRY RUN preview."
    echo "   To execute for real, run:"
    echo "   rsync -avh --delete --exclude='.Spotlight-*' --exclude='.fseventsd' --exclude='.Trashes' --exclude='.DS_Store' '$SRC/' '$DEST/'"
}


# ============================================================
# 6. 统计每年照片/视频数量和大小
#    帮助了解历年数据分布
# ============================================================
yearly_stats() {
    local DISK_PATH="${1:-.}"

    echo "=== Yearly Photo/Video Statistics ==="
    echo "Path: $DISK_PATH"
    echo ""
    printf "%-6s %10s %10s %12s\n" "Year" "Photos" "Videos" "Total Size"
    printf "%-6s %10s %10s %12s\n" "----" "------" "------" "----------"

    for year_dir in "$DISK_PATH"/20*/; do
        if [ -d "$year_dir" ]; then
            local year=$(basename "$year_dir")
            local photos=$(find "$year_dir" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.cr2" -o -iname "*.cr3" -o -iname "*.arw" -o -iname "*.dng" -o -iname "*.raw" -o -iname "*.nef" -o -iname "*.heic" \) 2>/dev/null | wc -l | tr -d ' ')
            local videos=$(find "$year_dir" -type f \( -iname "*.mp4" -o -iname "*.mov" -o -iname "*.avi" -o -iname "*.mkv" -o -iname "*.mts" \) 2>/dev/null | wc -l | tr -d ' ')
            local size=$(du -sh "$year_dir" 2>/dev/null | cut -f1)
            printf "%-6s %10s %10s %12s\n" "$year" "$photos" "$videos" "$size"
        fi
    done
}

# 使用方法: yearly_stats /Volumes/WD12TB-A


# ============================================================
# 7. 查找零散文件（不在任何年份目录内的文件）
# ============================================================
find_orphan_files() {
    local DISK_PATH="${1:-.}"

    echo "=== Orphan Files (not in year folders) ==="
    find "$DISK_PATH" -maxdepth 1 -type f | while read -r f; do
        local size=$(du -sh "$f" 2>/dev/null | cut -f1)
        echo "  $size  $(basename "$f")"
    done
}


# ============================================================
# 快速参考
# ============================================================
echo ""
echo "=== 磁盘管理工具集 ==="
echo "Available commands:"
echo "  generate_inventory /path    — 生成目录清单"
echo "  find_duplicates /path       — 查找重复文件"
echo "  organize_by_date src dest   — 按日期整理照片视频"
echo "  check_disk_health /dev/diskN — SMART 健康检查"
echo "  mirror_disks src dest       — 镜像同步两块硬盘"
echo "  yearly_stats /path          — 统计每年照片视频数量"
echo "  find_orphan_files /path     — 查找根目录零散文件"
echo ""
echo "Dependencies: brew install exiftool fdupes smartmontools"
