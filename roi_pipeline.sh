#!/bin/bash

echo "🚀 Step 1: ROI提取和检测..."
python detectAndConvert.py --run_extract --run_detect
if [ $? -ne 0 ]; then
    echo "❌ detectAndConvert.py 运行失败，终止流程。"
    exit 1
fi

echo "🚀 Step 2: 切换到编码目录..."
cd /root/h264_qpblock/build || exit

echo "🚀 Step 3: 执行 ROI 编码..."
./h264_qpblock /root/dataset/input.mp4 /root/dataset/output.mp4 \
    --roi_folder ./runs/roi_per_frame \
    -baseqp 25
if [ $? -ne 0 ]; then
    echo "❌ h264_qpblock 编码失败，终止流程。"
    exit 1
fi

echo "🚀 Step 4: H264转封装为MP4..."
ffmpeg -y -f h264 -i /root/dataset/output.mp4 -c copy /root/dataset/output_mux.mp4
if [ $? -ne 0 ]; then
    echo "❌ FFmpeg 封装失败，终止流程。"
    exit 1
fi

echo "🚀 Step 5: 精度评估中..."
cd /root
python /root/eval_yolo_precision.py \
  --gt_frames_dir ./dataset/frames \
  --orig_video /root/dataset/input.mp4 \
  --pred_video /root/dataset/output_mux.mp4
if [ $? -ne 0 ]; then
    echo "❌ 精度评估失败。"
    exit 1
fi

echo "✅ 全部流程完成！"
