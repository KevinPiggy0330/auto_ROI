#!/usr/bin/env bash
set -e  # 只要有命令出错就立刻退出

# 创建输出目录（如果没传挂载，也不会报错）
mkdir -p "${OUTPUT_DIR:-/outputs}"
mkdir -p "${DATA_DIR:-/dataset}"
mkdir -p "${WEIGHTS_DIR:-/weights}"

# 打印 GPU 信息（如果能找到 nvidia-smi）
if command -v nvidia-smi >/dev/null 2>&1; then
  echo "==== NVIDIA SMI ===="
  nvidia-smi || true
fi

echo "[entrypoint] DATA_DIR=${DATA_DIR:-/dataset}"
echo "[entrypoint] OUTPUT_DIR=${OUTPUT_DIR:-/outputs}"
echo "[entrypoint] WEIGHTS_DIR=${WEIGHTS_DIR:-/weights}"

# 执行传入容器的命令
exec "$@"
