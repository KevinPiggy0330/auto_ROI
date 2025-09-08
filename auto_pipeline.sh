#!/bin/bash
# ===============================================================
# ROI 编码 + 抽帧压缩 一体化流程脚本
# ===============================================================

set -e
START_TIME=$SECONDS

# ------------------ Step 1: ROI 提取和检测 ------------------
echo "🚀 Step 1: ROI提取和检测..."
python detectAndConvert.py --run_extract --run_detect --quiet #是否逐帧输出
if [ $? -ne 0 ]; then
    echo "❌ detectAndConvert.py 运行失败，终止流程。"
    exit 1
fi

# ------------------ Step 2: ROI 编码 ------------------
echo "🚀 Step 2: 切换到编码目录..."
cd /root/h264_qpblock/build || exit

echo "🚀 Step 3: 执行 ROI 编码..."
./h264_qpblock /root/dataset/input.mp4 /root/dataset/output.h264 \
    --roi_folder ./runs/roi_per_frame \
    -baseqp 25
if [ $? -ne 0 ]; then
    echo "❌ h264_qpblock 编码失败，终止流程。"
    exit 1
fi

# ------------------ Step 3: remux h264 -> mp4 ------------------
echo "🚀 Step 4: H264转封装为MP4..."
ffmpeg -y -f h264 -i /root/dataset/output.h264 -c copy /root/dataset/output_mux.mp4
if [ $? -ne 0 ]; then
    echo "❌ FFmpeg 封装失败，终止流程。"
    exit 1
fi

# ------------------ Step 4: 精度评估 ------------------
echo "🚀 Step 5: 精度评估中..."
cd /root
python /root/eval_yolo_precision.py \
  --gt_frames_dir /root/dataset/frames \
  --orig_video /root/dataset/input.mp4 \
  --pred_video /root/dataset/output_mux.mp4
if [ $? -ne 0 ]; then
    echo "❌ 精度评估失败。"
    exit 1
fi

# ------------------ Step 5: 抽帧压缩 ------------------
echo "🚀 Step 6: 启动抽帧压缩..."
# 使用 compress.sh 进行压缩
bash /root/frame_compress/compress.sh /root/dataset/output_mux.mp4 /root/dataset/output_final.mp4
if [ $? -ne 0 ]; then
    echo "❌ compress.sh 抽帧压缩失败，终止流程。"
    exit 1
fi

# ------------------ 全流程完成 ------------------
END_TIME=$SECONDS
ELAPSED_TIME=$(( END_TIME - START_TIME ))

echo "✅ 全部流程完成！最终结果在 /root/dataset/output_final.mp4"
echo "⏱ 总耗时: ${ELAPSED_TIME} 秒"
