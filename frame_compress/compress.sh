#!/bin/bash
# =================================================================
# 高效保留I帧+自适应抽帧脚本（极速模式）
# =================================================================
START_TIME=$SECONDS

if [ $# -lt 2 ]; then
    echo "用法: $0 <输入视频> <输出视频>"
    exit 1
fi

INPUT="$1"
OUTPUT="$2"
# TARGET_FPS=${3:-15}

# 安全防护：检查输入文件是否存在
if [ ! -f "$INPUT" ]; then
    echo "错误：输入文件不存在！"
    exit 1
fi

# 安全防护：避免输出文件与输入文件相同
if [ "$INPUT" == "$OUTPUT" ]; then
    echo "错误：输出文件不能与输入文件同名！"
    exit 1
fi

# 检查FFmpeg是否存在
if ! command -v ffmpeg &> /dev/null; then
    echo "错误：FFmpeg未安装！"
    echo "请安装FFmpeg：sudo apt install ffmpeg"
    exit 1
fi

# 获取视频基本信息（只读操作）
get_video_info() {
    ffprobe -v error -select_streams v:0 \
            -show_entries stream=r_frame_rate,duration,bit_rate \
            -of default=nw=1 "$1"
}

# 安全获取视频信息
VIDEO_INFO=$(get_video_info "$INPUT")
ORIGINAL_FPS=$(echo "$VIDEO_INFO" | grep r_frame_rate | awk -F'=' '{print $2}' | awk -F'/' '{print $1/$2}')
ORIGINAL_DURATION=$(echo "$VIDEO_INFO" | grep duration | awk -F'=' '{print $2}')
ORIGINAL_BITRATE=$(echo "$VIDEO_INFO" | grep bit_rate | awk -F'=' '{print $2}')

# 如果无法获取时长，使用备用方法（只读操作）
if [ -z "$ORIGINAL_DURATION" ]; then
    ORIGINAL_DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT")
fi

# 如果码率为空，估算码率
if [ -z "$ORIGINAL_BITRATE" ]; then
    ORIGINAL_BITRATE=$(awk -v size="$ORIGINAL_SIZE" -v duration="$ORIGINAL_DURATION" 'BEGIN { printf "%.0f", (size * 8) / duration }')
fi

ORIGINAL_BITRATE=$(awk -v bitrate="$ORIGINAL_BITRATE" 'BEGIN { printf "%.0f", bitrate / 1000 }')

# 网络状态检测
get_network_status() {
    local status_file="$(pwd)/current_network_status"
    if [ -f "$status_file" ]; then
        cat "$status_file"
    else
        echo "unknown"
    fi
}

# 获取当前网络状态
NETWORK_STATUS=$(get_network_status)

# 根据网络状态设置压缩参数
case "$NETWORK_STATUS" in
    "excellent")
        # excellent状态：使用原视频
        echo "网络状态优秀，直接使用原始视频帧率..."
        cp "$INPUT" "$OUTPUT"
        exit 0
        ;;
    "good")
        TARGET_FPS=$(printf "%.0f" "$(echo "$ORIGINAL_FPS * 0.8" | bc -l)")
        SELECT_FILTER="select='eq(pict_type\,I)+gte(n\,0)',setpts=PTS+0,mpdecimate=hi=64*20:lo=64*12:frac=0.2"
        BUF_SIZE=$(awk -v bitrate="$ORIGINAL_BITRATE" 'BEGIN { printf "%.0f", bitrate * 0.8 }')
        ;;
    "fair")
        TARGET_FPS=$(printf "%.0f" "$(echo "$ORIGINAL_FPS * 0.6" | bc -l)")
        SELECT_FILTER="select='eq(pict_type\,I)+gte(n\,0)',setpts=PTS+0,mpdecimate=hi=64*16:lo=64*10:frac=0.25"
        BUF_SIZE=$(awk -v bitrate="$ORIGINAL_BITRATE" 'BEGIN { printf "%.0f", bitrate * 0.6 }')
        ;;
    "poor"|*)
        TARGET_FPS=$(printf "%.0f" "$(echo "$ORIGINAL_FPS * 0.3" | bc -l)")
        SELECT_FILTER="select='eq(pict_type\,I)+gte(n\,0)',setpts=PTS+0,mpdecimate=hi=64*12:lo=64*8:frac=0.3"
        BUF_SIZE=$(awk -v bitrate="$ORIGINAL_BITRATE" 'BEGIN { printf "%.0f", bitrate * 0.3 }')
        ;;
esac

echo "=============================================="
echo "原始视频信息"
echo "----------------------------------------------"
echo "输入文件:   $INPUT"
echo "原始帧率:   $ORIGINAL_FPS fps"
echo "原始码率:   $ORIGINAL_BITRATE kbps"
echo "原始时长:   $ORIGINAL_DURATION 秒"
echo "网络状态：  $NETWORK_STATUS"
echo "目标帧率:   $TARGET_FPS fps"
echo "=============================================="

# 构建选择表达式：
# 1. 所有 I 帧保留（eq(pict_type\,I)）
# 2. 其他帧按照目标帧率抽帧

# 时序抽帧（容易出现浮点运算不准，不推荐）
# SELECT_FILTER="select='eq(pict_type\,I)+between(t\,0\,999999)*mod(t\,1/$TARGET_FPS)',setpts=PTS+0"
# 运动状态抽帧
# SELECT_FILTER="select='eq(pict_type\,I)+gte(n\,0)',setpts=PTS+0,mpdecimate=hi=64*12:lo=64*8:frac=0.3" 

# # 获取原始视频I帧数量
# I_FRAME_COUNT=$(ffprobe -v error -show_frames "$INPUT" 2>/dev/null | grep 'pict_type' | grep -c 'I')
# # 预估筛选后的帧数 = I帧数 + (总帧数 / 目标帧率)
# SELECTED_FRAMES=$(awk -v i="$I_FRAME_COUNT" -v d="$ORIGINAL_DURATION" -v fps="$TARGET_FPS" 'BEGIN { frames = i + d * fps; printf "%d", frames }')

# echo ""
# echo "=============================================="
# echo "帧数预估信息"
# echo "----------------------------------------------"
# echo "I帧数量:      $I_FRAME_COUNT"
# echo "预估筛选帧数: $SELECTED_FRAMES"
# echo "=============================================="

# 开始压缩
# 如果降低画质，将136行改为23 fast
# 如果需要声音，将140行内容替换为-c:a aac -b:a 64k \
ffmpeg -i "$INPUT" \
       -vf "$SELECT_FILTER" \
       -c:v libx264 -crf 18 -preset slow \
       -maxrate "${ORIGINAL_BITRATE}k" -bufsize "${BUF_SIZE}k" \
       -pix_fmt yuv420p \
       -r $TARGET_FPS \
       -an \
       -movflags +faststart \
       -y "$OUTPUT" >/dev/null 2>&1   

END_TIME=$SECONDS
ELAPSED_TIME=$(( END_TIME - START_TIME ))
echo "✅ 视频压缩完成，总耗时: ${ELAPSED_TIME} 秒"

# 验证输出
FINAL_FPS_RAW=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=nw=1 "$OUTPUT" 2>/dev/null)
FINAL_DURATION_RAW=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$OUTPUT" 2>/dev/null)

# 解析帧率
if [[ "$FINAL_FPS_RAW" =~ ([0-9]+)/([0-9]+) ]]; then
    FINAL_FPS=$((BASH_REMATCH[1] / BASH_REMATCH[2]))
else
    FINAL_FPS="N/A"
fi

# 解析时长
if [[ "$FINAL_DURATION_RAW" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    FINAL_DURATION=$(awk 'BEGIN{printf "%.2f", "'$FINAL_DURATION_RAW'"}')
else
    FINAL_DURATION="N/A"
fi

# 计算误差
if [[ "$FINAL_DURATION" != "N/A" && "$ORIGINAL_DURATION" != "N/A" ]]; then
    DURATION_DIFF=$(awk -v orig="$ORIGINAL_DURATION" -v final="$FINAL_DURATION" 'BEGIN {diff = (final - orig)/orig*100; printf "%.2f%%", diff}')
else
    DURATION_DIFF="N/A"
fi

# 获取文件大小函数
get_file_size() {
    local file="$1"
    if [ -f "$file" ]; then
        stat --printf="%s" "$file" 2>/dev/null || du -b "$file" | cut -f1
    else
        echo "0"
    fi
}

# 获取原始视频大小
ORIGINAL_SIZE=$(get_file_size "$INPUT")
# 获取压缩后视频大小
COMPRESSED_SIZE=$(get_file_size "$OUTPUT")

# 计算压缩率
if [ "$ORIGINAL_SIZE" -gt 0 ]; then
    COMPRESSION_RATIO=$(awk -v orig="$ORIGINAL_SIZE" -v comp="$COMPRESSED_SIZE" 'BEGIN { ratio = (orig - comp) / orig * 100; printf "%.2f%%", ratio }')
else
    COMPRESSION_RATIO="N/A"
fi

echo "=============================================="
echo "压缩视频信息"
echo "----------------------------------------------"
echo "输出文件:   $OUTPUT"
echo "输出帧率:   $FINAL_FPS fps"
echo "原始大小:   $(awk -v size="$ORIGINAL_SIZE" 'BEGIN { printf "%.2f MB", size / 1024 / 1024 }')"
echo "压缩后大小: $(awk -v size="$COMPRESSED_SIZE" 'BEGIN { printf "%.2f MB", size / 1024 / 1024 }')"
echo "压缩率:     $COMPRESSION_RATIO"
echo "原始时长:   $ORIGINAL_DURATION 秒"
echo "最终时长:   $FINAL_DURATION 秒"
echo "时长误差:   $DURATION_DIFF"
echo "=============================================="
# ffprobe -v error -show_entries frame=pkt_pts_time,pict_type -of default=nw=1 "$OUTPUT" > output_frames.txt