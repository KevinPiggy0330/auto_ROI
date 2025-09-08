# 选择 PyTorch 官方镜像，带 CUDA 12.1 + cuDNN
FROM pytorch/pytorch:2.4.1-cuda12.1-cudnn9-runtime

ENV DEBIAN_FRONTEND=noninteractive TZ=Asia/Shanghai

# 安装系统依赖：ffmpeg + x264 + OpenCV 常见依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg x264 libx264-dev \
    libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 git curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# 安装 Python 依赖
COPY requirements.txt /workspace/requirements.txt
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# 复制项目源码
COPY . /workspace

# 设置入口脚本
COPY entrypoint.sh /workspace/entrypoint.sh
RUN chmod +x /workspace/entrypoint.sh

ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 \
    DATA_DIR=/data OUTPUT_DIR=/outputs

ENTRYPOINT ["/workspace/entrypoint.sh"]

# 默认启动命令（可以在 docker run 覆盖）
CMD ["python", "detectAndConvert.py"]
