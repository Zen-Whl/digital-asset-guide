#!/bin/bash
# ============================================================
# rsync 硬盘迁移指南 — Disk Migration with rsync
# 适用于 macOS / Linux
# ============================================================

# ============================================================
# 基础用法：从老硬盘拷贝到新硬盘
# ============================================================

# 最基本的拷贝（不带校验，速度最快，但无法发现静默错误）
# rsync -avh /Volumes/OldDisk/ /Volumes/WD12TB-A/FromOldDisk/

# 推荐用法：拷贝时同步校验（老盘只读一遍，不额外消耗寿命）
rsync_with_checksum() {
    local SRC="$1"    # 例: /Volumes/OldDisk-3TB/
    local DEST="$2"   # 例: /Volumes/WD12TB-A/Migration/OldDisk-3TB/

    if [ -z "$SRC" ] || [ -z "$DEST" ]; then
        echo "用法: rsync_with_checksum /Volumes/源硬盘/ /Volumes/目标硬盘/目标文件夹/"
        echo ""
        echo "示例:"
        echo "  rsync_with_checksum /Volumes/Seagate3TB-2015/ /Volumes/WD12TB-A/Migration/SG3TB-2015/"
        return 1
    fi

    echo "=== rsync Migration ==="
    echo "源硬盘: $SRC"
    echo "目标:   $DEST"
    echo "开始时间: $(date)"
    echo ""

    # 创建目标目录
    mkdir -p "$DEST"

    # -a  归档模式（保留权限、时间戳、符号链接等所有属性）
    # -v  显示正在拷贝的文件名
    # -h  文件大小以人类可读格式显示（KB/MB/GB）
    # --checksum  用 MD5 校验文件内容（而非仅比较大小和时间戳）
    # --progress  显示每个文件的传输进度和速度
    # --log-file  记录完整日志，事后可以检查
    # --exclude   排除 macOS 系统文件（这些不需要迁移）

    rsync -avh \
        --checksum \
        --progress \
        --log-file="${DEST}/rsync_log_$(date +%Y%m%d_%H%M%S).txt" \
        --exclude=".Spotlight-*" \
        --exclude=".fseventsd" \
        --exclude=".Trashes" \
        --exclude=".DS_Store" \
        --exclude=".TemporaryItems" \
        "$SRC" "$DEST"

    local EXIT_CODE=$?

    echo ""
    echo "结束时间: $(date)"

    if [ $EXIT_CODE -eq 0 ]; then
        echo "✅ 拷贝完成，所有文件校验通过"
    else
        echo "⚠️  rsync 退出码: $EXIT_CODE"
        echo "   请检查日志文件了解详情"
        echo "   常见退出码:"
        echo "   23 = 部分文件无法读取（可能是坏扇区）"
        echo "   24 = 部分文件在传输过程中消失"
        echo "   11 = 输出流写入错误（目标盘可能满了）"
    fi
}


# ============================================================
# 分步操作指南（适合第一次使用的用户）
# ============================================================

show_step_by_step() {
    cat << 'GUIDE'

========================================
  macOS 下用 rsync 迁移老硬盘 — 分步指南
========================================

第 1 步：插入两块硬盘
  - 把老硬盘和目标大硬盘都插到电脑上
  - 打开 Finder 确认两块盘都已挂载
  - 记下它们的挂载路径，通常是:
      /Volumes/老硬盘名称/
      /Volumes/新硬盘名称/

第 2 步：打开终端（Terminal）
  - 在 Spotlight 搜索 "Terminal" 或
  - 打开 应用程序 → 实用工具 → 终端

第 3 步：先预览，不实际拷贝（dry-run）
  执行以下命令（把路径替换成你自己的）:

    rsync -avhn --checksum \
      --exclude=".Spotlight-*" \
      --exclude=".fseventsd" \
      --exclude=".Trashes" \
      --exclude=".DS_Store" \
      /Volumes/Seagate3TB-2015/ \
      /Volumes/WD12TB-A/Migration/SG3TB-2015/

  注意: -n 代表 dry-run（模拟运行），不会真的拷贝任何文件
  这一步让你确认:
    ✓ 源路径和目标路径是否正确
    ✓ 要拷贝的文件列表是否符合预期
    ✓ 没有把源和目标搞反（这一点很重要！）

第 4 步：正式拷贝
  确认无误后，去掉 -n，加上 --progress 和 --log-file:

    rsync -avh --checksum --progress \
      --log-file="/Volumes/WD12TB-A/rsync_log_SG3TB.txt" \
      --exclude=".Spotlight-*" \
      --exclude=".fseventsd" \
      --exclude=".Trashes" \
      --exclude=".DS_Store" \
      /Volumes/Seagate3TB-2015/ \
      /Volumes/WD12TB-A/Migration/SG3TB-2015/

  然后等待。3TB 数据通过 USB 3.0 大约需要 8-12 小时。
  建议晚上睡前开始，第二天早上检查结果。

  ⚠️ 关键提醒：源路径末尾的 / 斜杠很重要！
     /Volumes/OldDisk/   → 拷贝 OldDisk 里面的内容
     /Volumes/OldDisk    → 拷贝 OldDisk 这个文件夹本身
     一般你想要的是前者（带斜杠）

第 5 步：检查结果
  - 查看终端输出，确认最后一行是否有错误
  - 打开日志文件检查是否有 "failed" 或 "error" 字样:

    grep -i "error\|failed" /Volumes/WD12TB-A/rsync_log_SG3TB.txt

  - 在目标文件夹里随机打开几十张照片和几段视频
  - 如果一切正常，这块老硬盘的迁移就完成了

第 6 步：如果中途断了怎么办？
  直接重新运行同一条 rsync 命令即可。
  rsync 会自动跳过已经成功拷贝的文件，只传输剩余的。
  这是 rsync 最大的优势 — 支持断点续传。

GUIDE
}


# ============================================================
# 拷贝后的抽样验证（不需要重读老盘）
# ============================================================

spot_check() {
    local DIR="$1"
    local COUNT="${2:-30}"

    if [ -z "$DIR" ]; then
        echo "用法: spot_check /Volumes/WD12TB-A/Migration/SG3TB-2015/ [抽样数量]"
        return 1
    fi

    echo "=== 抽样验证 ==="
    echo "目录: $DIR"
    echo "抽样数量: $COUNT"
    echo ""

    # 随机抽取照片文件，尝试用 sips 验证（macOS 内置图像工具）
    echo "--- 验证照片 ---"
    find "$DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.cr2" -o -iname "*.cr3" -o -iname "*.heic" \) | \
        shuf | head -n "$COUNT" | while read -r img; do
            # sips -g pixelWidth 能验证图片是否可正常解码
            if sips -g pixelWidth "$img" > /dev/null 2>&1; then
                echo "  ✅ $(basename "$img")"
            else
                echo "  ❌ CORRUPTED: $img"
            fi
        done

    echo ""
    echo "--- 验证视频（检查前几帧）---"
    # 需要 ffprobe（brew install ffmpeg）
    find "$DIR" -type f \( -iname "*.mp4" -o -iname "*.mov" -o -iname "*.avi" -o -iname "*.mkv" -o -iname "*.mts" \) | \
        shuf | head -n 10 | while read -r vid; do
            if ffprobe -v error "$vid" > /dev/null 2>&1; then
                echo "  ✅ $(basename "$vid")"
            else
                echo "  ❌ CORRUPTED: $vid"
            fi
        done

    echo ""
    echo "=== 验证完成 ==="
    echo "如果以上全部显示 ✅，数据迁移可信度很高"
    echo "如果有 ❌，需要从老盘重新拷贝对应文件"
}


# ============================================================
# 快速参考
# ============================================================
echo ""
echo "=== rsync 硬盘迁移工具 ==="
echo "命令:"
echo "  rsync_with_checksum /Volumes/源盘/ /Volumes/目标盘/文件夹/"
echo "  show_step_by_step                    — 显示分步操作指南"
echo "  spot_check /Volumes/目标盘/文件夹/   — 拷贝后抽样验证"
echo ""
echo "依赖: rsync (macOS 自带), ffprobe (可选: brew install ffmpeg)"
