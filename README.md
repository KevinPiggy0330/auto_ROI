# Auto ROI — 容器化使用说明

本镜像封装了 **ROI 检测 → ROI 编码 (h264_qpblock) → 视频封装 → 精度评估 → 抽帧压缩** 的完整流水线。用户无需安装 CMake / Python 依赖 / 编译器等，**拉取镜像 + 挂载数据即可运行**。


## 1. 环境准备

- **Docker 20+**
- （可选）NVIDIA GPU + [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)
- 能访问镜像仓库 `ghcr.io`


## 2. 准备宿主机目录

在宿主机准备以下目录结构：

```
/path/to/project/
├── dataset/          # 输入/存放中间数据（至少包含 input.mp4）
│   └── input.mp4
├── outputs/          # 输出结果
└── weights/          # (可选) 模型权重，如果不挂载需要联网下载
```

## 3. 拉取镜像

```bash
docker pull ghcr.io/kevinpiggy0330/auto_roi:1.0.0
```

## 4. 项目目录
```
auto_ROI/
├── auto_pipeline.sh         # ROI + 抽帧一体化流程脚本
├── detectAndConvert.py      # ROI 检测脚本
├── roi_pipeline.sh          # ROI 编码单步流程脚本（供测试）
├── eval_yolo_precision.py   # ROI 编码精度评估脚本
├── frame_compress/          # 抽帧压缩工具
├── h264_qpblock/            # ROI 感知 H.264 编码器
├── dataset/                 # 输入/输出视频目录（挂载）
├── weights/                 # 模型权重目录（挂载）
├── requirements.txt
├── Dockerfile
├── entrypoint.sh
└── .dockerignore
```

## 5. 一键运行

### GPU 模式
```bash
docker run --rm -it --gpus all \
  -v /path/to/project/dataset:/dataset \
  -v /path/to/project/outputs:/outputs \
  -v /path/to/project/weights:/weights \
  ghcr.io/kevinpiggy0330/auto_roi:1.0.0 \
  bash auto_pipeline.sh --base_qp 25
```

### CPU 模式
```bash
docker run --rm -it \
  -v /path/to/project/dataset:/dataset \
  -v /path/to/project/outputs:/outputs \
  -v /path/to/project/weights:/weights \
  ghcr.io/kevinpiggy0330/auto_roi:1.0.0 \
  bash auto_pipeline.sh --base_qp 25
```

**输出结果**  
- `/outputs/output.h264` → ROI 编码后 H.264 裸流  
- `/outputs/output_mux.mp4` → MP4 封装  
- `/outputs/output_final.mp4` → 抽帧压缩结果  

