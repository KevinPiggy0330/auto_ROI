"""
    YOLO ROI 生成脚本 detectAndConvert.py
    --------------------------------------

    功能：
    - 从视频中抽取帧图像
    - 使用 YOLOv5 进行目标检测
    - 将每帧检测结果转为 ROI 参数，输出为 .txt 文件
    · frame_xxxx_multi.txt  每个目标一个 ROI
    · frame_xxxx_merge.txt  (可选) 合并所有目标为一个大 ROI

    使用方法：
    1. 抽帧 + 检测 + 转换：
    python detectAndConvert.py --run_extract --run_detect

    2. 已有检测结果，只做转换：
    python detectAndConvert.py --labels_dir ./runs/detect/roi_results/labels

    参数说明：
    --video         视频路径（默认 ./../dataset/input.mp4）
    --frames_dir    抽帧输出路径
    --yolo_repo     YOLOv5 路径
    --labels_dir    标签路径（不跑YOLO时使用）
    --roi_dir       ROI输出路径（默认 ./roi_per_frame）
    --run_extract   是否执行抽帧
    --run_detect    是否执行YOLO检测
    --merge_roi     是否保存合并ROI（默认不生成）
    --w / --h       图像宽高
    --class_id      指定目标类别（-1为全部）
    --qp            QP值（默认10.0）

"""
import os
import cv2
import torch
from pathlib import Path
import subprocess
import argparse
from ultralytics import YOLO

# ---------- 功能函数 ---------- #
def extract_frames(video_path, output_dir, frame_interval=1):
    cap = cv2.VideoCapture(video_path)
    os.makedirs(output_dir, exist_ok=True)
    count = saved = 0
    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break
        if count % frame_interval == 0:
            out_path = os.path.join(output_dir, f"frame_{count:04d}.jpg")
            try:
                cv2.imwrite(out_path, frame)
                saved += 1
            except Exception as e:
                print(f"⚠️ 第 {count} 帧保存失败: {e}")
        count += 1
    cap.release()
    print(f"共保存 {saved} 张帧图像到 {output_dir}（按原始编号）")
    return output_dir



def run_yolo_detection(image_dir, weights="yolov8n.pt", imgsz=640, conf=0.25, quiet=False):
    if quiet:
        import logging
        from ultralytics.utils import LOGGER
        LOGGER.setLevel(logging.WARNING)  # 只保留进度条等必要信息
    print(f"🔍 YOLOv8 检测中，路径: {image_dir}")
    model = YOLO(weights)
    model.predict(
        source=image_dir,
        imgsz=imgsz,
        conf=conf,
        save_txt=True,
        save=True,
        project="runs/detect",
        name="roi_results",
        exist_ok=True,
        workers=0,           # 避免多进程导致输出花屏
        verbose=not quiet    # ← 关键：安静模式只显示进度条
    )
    print("✅ 检测完成, 输出已保存")
    return "./runs/detect/roi_results/labels"



def convert_and_split(label_dir, out_dir, img_w, img_h,
                      target_class=-1, qp_value=10.0, save_merge=True):
    """
    YOLO txt -> 逐帧 ROI 文件
      · frame_XXXX_multi.txt  : 多目标
      · frame_XXXX_merge.txt  : 合并（可选）
    """
    os.makedirs(out_dir, exist_ok=True)

    for txt_path in Path(label_dir).glob("*.txt"):
        frame = txt_path.stem
        boxes, rois = [], []

        with open(txt_path) as fin:
            for line in fin:
                cls, x, y, w, h = map(float, line.split())
                if target_class != -1 and int(cls) != target_class:
                    continue
                x1 = int((x - w/2) * img_w)
                y1 = int((y - h/2) * img_h)
                x2 = int((x + w/2) * img_w)
                y2 = int((y + h/2) * img_h)
                boxes.append((x1, y1, x2, y2))
                rois.append(f"{x1},{y1},{x2},{y2}:{qp_value}")

        if rois:
            (Path(out_dir)/f"{frame}_multi.txt").write_text("\n".join(rois))

        if save_merge and boxes:
            mx1 = min(b[0] for b in boxes); my1 = min(b[1] for b in boxes)
            mx2 = max(b[2] for b in boxes); my2 = max(b[3] for b in boxes)
            merged = f"{mx1},{my1},{mx2},{my2}:{qp_value}"
            (Path(out_dir)/f"{frame}_merge.txt").write_text(merged+"\n")

    print(f"✅ ROI 已写入 {out_dir}   (merge={'ON' if save_merge else 'OFF'})")


# ---------- 主程序 ---------- #
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="YOLO ROI 生成脚本")
    parser.add_argument("--video", default="./../dataset/input.mp4")
    parser.add_argument("--frames_dir", default="./../dataset/frames")
    parser.add_argument("--labels_dir", default="./runs/detect/roi_results/labels",
                        help="已存在的label目录，若不跑YOLO则直接用此路径")
    parser.add_argument("--run_extract", action="store_true", help="执行抽帧")
    parser.add_argument("--run_detect", action="store_true", help="执行YOLO检测")
    parser.add_argument("--weights", default="./../weights/yolov8n.pt", help="YOLO权重文件") 
    parser.add_argument("--roi_dir", default="./runs/roi_per_frame", help="ROI 输出目录")
    parser.add_argument("--merge_roi", action="store_true",
                        help="生成每帧合并 ROI 文件（默认不生成）")
    parser.add_argument("--class_id", type=int, default=-1)
    parser.add_argument("--quiet", action="store_true", help="静默模式：仅显示进度条，屏蔽逐帧日志")
    parser.add_argument("--imgsz", type=int, default=640)
    parser.add_argument("--conf", type=float, default=0.25)
    parser.add_argument("--w", type=int, default=1920)
    parser.add_argument("--h", type=int, default=1080)
    parser.add_argument("--qp", type=float, default=10.0)
    args = parser.parse_args()

    # 1. 抽帧
    if args.run_extract:
        extract_frames(args.video, args.frames_dir, frame_interval=1)

    # 2. YOLO 检测
    label_path = args.labels_dir
    if args.run_detect:
        label_path = run_yolo_detection(
            args.frames_dir,
            weights=args.weights,
            imgsz=args.imgsz,
            conf=args.conf,
            quiet=args.quiet
        )


    # 3. ROI 转换
    convert_and_split(
        label_path,
        args.roi_dir,
        img_w=args.w,
        img_h=args.h,
        target_class=args.class_id,
        qp_value=args.qp,
        save_merge=args.merge_roi
    )
