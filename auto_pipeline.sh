#!/usr/bin/env bash
# ===============================================================
# 通用 Docker 版：ROI 检测 → ROI 编码 → 封装 → 评估 → 抽帧压缩
# - 不依赖固定路径；自动基于脚本位置定位工程根目录
# - 支持环境变量/参数覆盖输入输出位置
#   环境变量：DATA_DIR=/dataset  OUTPUT_DIR=/outputs  WEIGHTS_DIR=/weights
#   参数：--input /path/video.mp4  --base_qp 25
# ===============================================================

set -euo pipefail

# ---------- 基础定位 ----------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
cd "$SCRIPT_DIR"  # 工程根：包含 detectAndConvert.py、h264_qpblock/ 等

# 默认目录（可被环境变量覆盖）
DATA_DIR="${DATA_DIR:-/dataset}"
OUTPUT_DIR="${OUTPUT_DIR:-/outputs}"
WEIGHTS_DIR="${WEIGHTS_DIR:-/weights}"

# 默认参数（可被命令行覆盖）
INPUT_VIDEO="${INPUT_VIDEO:-$DATA_DIR/input.mp4}"
BASE_QP="${BASE_QP:-25}"

# ---------- 简易参数解析 ----------
# 用法：./auto_pipeline.sh --input /data/xxx.mp4 --base_qp 25
while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      INPUT_VIDEO="$2"; shift 2;;
    --base_qp)
      BASE_QP="$2"; shift 2;;
    *)
      echo "Unknown arg: $1"; exit 2;;
  esac
done

# ---------- 准备目录/映射 ----------
mkdir -p "$OUTPUT_DIR"

# 将挂载目录映射为工程内的相对路径
ln -sfn "$DATA_DIR"    "$SCRIPT_DIR/dataset"
ln -sfn "$OUTPUT_DIR"  "$SCRIPT_DIR/outputs"
# 如需权重同理：ln -sfn "$WEIGHTS_DIR" "$SCRIPT_DIR/weights"  # 若代码有用到

if [[ ! -f "$INPUT_VIDEO" ]]; then
  echo "❌ 找不到输入视频：$INPUT_VIDEO"
  echo "   请通过 -v 挂载数据目录到容器，比如： -v /path/to/dataset:/dataset"
  exit 1
fi

echo "工程根:         $SCRIPT_DIR"
echo "数据目录(DATA): $DATA_DIR"
echo "输出目录(OUT):  $OUTPUT_DIR"
echo "输入视频:       $INPUT_VIDEO"
echo "基准QP:         $BASE_QP"
echo

# ===============================================================
# Step 1: ROI 提取与检测
# ===============================================================
echo "🚀 Step 1: ROI 提取与检测..."
# 兼容你原先脚本：detectAndConvert.py 默认读取 ./dataset/input.mp4 并输出 ./runs/roi_per_frame
# 如 detectAndConvert.py 支持自定义输入/输出参数，可在此补上参数。
python "$SCRIPT_DIR/detectAndConvert.py" --run_extract --run_detect --quiet || {
  echo "❌ detectAndConvert.py 运行失败"; exit 1;
}

ROI_DIR="$SCRIPT_DIR/runs/roi_per_frame"
if [[ ! -d "$ROI_DIR" ]]; then
  echo "⚠️ 未发现 ROI 结果目录：$ROI_DIR  —— 请确认 detectAndConvert.py 的输出位置"
fi

# ===============================================================
# Step 2: ROI 编码（h264_qpblock）
# ===============================================================
BIN_DIR="$SCRIPT_DIR/h264_qpblock/build"
BIN="$BIN_DIR/h264_qpblock"

# 如果二进制不存在，尝试现场构建（建议在 Dockerfile 构建阶段就完成编译）
if [[ ! -x "$BIN" ]]; then
  echo "未找到 h264_qpblock，可执行现场编译（建议在镜像构建时完成）"
  mkdir -p "$BIN_DIR"
  pushd "$BIN_DIR" >/dev/null
  if command -v cmake >/dev/null 2>&1; then
    cmake .. && make -j"$(nproc)"
  else
    echo "❌ 镜像缺少 cmake，无法编译 h264_qpblock。请在 Dockerfile 中添加编译步骤。"
    exit 1
  fi
  popd >/dev/null
fi

ENC_H264="$OUTPUT_DIR/output.h264"
echo "🚀 Step 2: 执行 ROI 编码..."
"$BIN" "$INPUT_VIDEO" "$ENC_H264" \
  --roi_folder "$ROI_DIR" \
  -baseqp "$BASE_QP" || { echo "❌ h264_qpblock 编码失败"; exit 1; }

# ===============================================================
# Step 3: Remux H.264 → MP4（无重编码）
# ===============================================================
MUX_MP4="$OUTPUT_DIR/output_mux.mp4"
echo "🚀 Step 3: H264 封装为 MP4..."
ffmpeg -y -f h264 -i "$ENC_H264" -c copy "$MUX_MP4" >/dev/null 2>&1 || {
  echo "❌ FFmpeg 封装失败"; exit 1;
}

# ===============================================================
# Step 4: 精度评估（可选）
# 兼容你原先参数：gt_frames 在 DATA_DIR/frames，原视频与预测视频分别为 DATA 与 OUT
# ===============================================================
echo "🚀 Step 4: 精度评估..."
python "$SCRIPT_DIR/eval_yolo_precision.py" \
  --gt_frames_dir "$DATA_DIR/frames" \
  --orig_video "$INPUT_VIDEO" \
  --pred_video "$MUX_MP4" || {
  echo "❌ 精度评估失败"; exit 1;
}

# ===============================================================
# Step 5: 抽帧压缩
# ===============================================================
FINAL_MP4="$OUTPUT_DIR/output_final.mp4"
echo "🚀 Step 5: 抽帧压缩..."
bash "$SCRIPT_DIR/frame_compress/compress.sh" "$MUX_MP4" "$FINAL_MP4" || {
  echo "❌ 抽帧压缩失败"; exit 1;
}

# ===============================================================
# 完成
# ===============================================================
echo
echo "全流程完成！"
echo "封装后视频: $MUX_MP4"
echo "最终结果:   $FINAL_MP4"
