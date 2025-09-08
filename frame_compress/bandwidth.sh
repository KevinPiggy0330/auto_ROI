#!/usr/bin/env bash

# 配置参数
DOWNLOAD_URL="https://dldir1.qq.com/qqfile/qq/PCQQ9.7.16/QQ9.7.16.29187.exe"  # 下载测试文件
TEST_URL="https://cloud.tencent.com/api/test-upload"  # 测速网站的上传接口
TEST_TIME=10  # 测试时间（秒）
LOG_FILE=$(pwd)/bandwidth_log.csv
MAX_LINES=100
INTERVAL=20

# 创建测试用的临时文件（50MB）
dd if=/dev/zero of=/tmp/testfile bs=1M count=50 2>/dev/null

# 初始化 CSV 文件头
echo "TIMESTAMP,DOWNLOAD_Mbps,UPLOAD_Mbps,NETWORK_CLASS" > "$LOG_FILE"

while true; do
    TIMESTAMP=$(date +"%H:%M:%S")

    # 下载速度测试
    download_info=$(curl -o /dev/null -s --max-time $TEST_TIME -w "%{speed_download}" "$DOWNLOAD_URL" | tr -cd '0-9.' | sed 's/^\.$//; s/\.\././g; s/^\([0-9]*\)\.\{0,1\}\([0-9]*\).*/\1.\2/')
    download_mbps=$(awk -v speed="$download_info" 'BEGIN { printf("%.2f", speed * 8 / 1000000) }')

    # 上传速度测试
    upload_info=$(curl -s --max-time $TEST_TIME -w "%{speed_upload}" -F "file=@/tmp/testfile" "$TEST_URL" | tr -cd '0-9.' | sed 's/^\.$//; s/\.\././g; s/^\([0-9]*\)\.\{0,1\}\([0-9]*\).*/\1.\2/')
    upload_mbps=$(awk -v speed="$upload_info" 'BEGIN { printf("%.2f", speed * 8 / 1000000) }')
        
    # 设置默认值
    [[ -z "$download_mbps" ]] && download_mbps=0
    [[ -z "$upload_mbps" ]] && upload_mbps=0

    # 网络状态分类（考虑上传和下载速度）
    class=$(awk -v down="$download_mbps" -v up="$upload_mbps" 'BEGIN {
        if (up < 2 * 8 || down< 1 * 8) {
            print "poor";
        } else if (up < 5 * 8 || down< 3 * 8) {
            print "fair";
        } else if (up < 10 * 8 || down< 5 * 8) {
            print "good";
        } else {
            print "excellent";
        }
    }')

    # 写入日志
    printf '%s,%.2f,%.2f,%s\n' \
      "$TIMESTAMP" "$download_mbps" "$upload_mbps" "$class" >> "$LOG_FILE"

    # 控制日志行数
    line_count=$(wc -l < "$LOG_FILE")
    if (( line_count > MAX_LINES )); then
        sed -i '1d' "$LOG_FILE"
    fi

    # 更新状态文件
    echo "$class" > "$(pwd)/current_network_status"

    # 终端输出
    echo "[$TIMESTAMP] Network Status: $class  Download: ${download_mbps} Mbps  Upload: ${upload_mbps} Mbps"

    sleep "$INTERVAL"
done

# 清理临时文件
trap 'rm -f /tmp/testfile' EXIT