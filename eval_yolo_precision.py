"""
快速评估：用 YOLO 在原始帧(GT) & ROI-编码视频(Pred)上跑推理，
GT=原始视频抽出的帧（直接复用detectAndConvert产生的frames_dir），
Pred=对编码后视频逐帧推理，计算COCO mAP，并衡量压缩率。
"""
import os, json, cv2, argparse, subprocess, shlex
from pathlib import Path
from tqdm import tqdm
from ultralytics import YOLO
from pycocotools.coco import COCO
from pycocotools.cocoeval import COCOeval

def natural_key(p: Path):
    # 自然排序：优先用文件名中的数字
    import re
    s = p.name
    return [int(t) if t.isdigit() else t for t in re.split(r'(\d+)', s)]

def list_frames(frames_dir: Path):
    exts = (".jpg", ".jpeg", ".png", ".bmp")
    files = [p for p in frames_dir.iterdir() if p.suffix.lower() in exts]
    return sorted(files, key=natural_key)

def video_to_frames(video_path: Path, out_dir: Path):
    cap = cv2.VideoCapture(str(video_path))
    out_dir.mkdir(parents=True, exist_ok=True)
    frames = []
    idx = 0
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT)) or 0
    pbar = tqdm(total=total if total > 0 else None, desc=f"Extract {video_path}")
    while cap.isOpened():
        ok, frame = cap.read()
        if not ok:
            break
        f = out_dir / f"{idx:05d}.jpg"
        cv2.imwrite(str(f), frame)
        frames.append(f)
        idx += 1
        if total > 0: pbar.update(1)
    cap.release()
    pbar.close()
    return frames

def frames_to_coco_json(frames, model, save_json, imgsz=640, conf=0.25, save_ann_only=False):
    coco_images, coco_anns = [], []
    ann_id = 1
    for img_id, f in enumerate(tqdm(frames, desc="YOLO Inference")):
        res = model(str(f), imgsz=imgsz, conf=conf, verbose=False)[0]
        h, w = res.orig_shape
        coco_images.append(
            {"file_name": f.name, "height": int(h), "width": int(w), "id": img_id}
        )
        # 预测框转 COCO
        if res.boxes is not None and len(res.boxes) > 0:
            for *box, score, cls in res.boxes.data.cpu().numpy():
                x1, y1, x2, y2 = box
                coco_anns.append(
                    {
                        "id": ann_id,
                        "image_id": img_id,
                        "category_id": int(cls) + 1,  # COCO类从1开始
                        "bbox": [float(x1), float(y1), float(x2 - x1), float(y2 - y1)],
                        "score": float(score),
                        "area": float(max(0.0, (x2 - x1)) * max(0.0, (y2 - y1))),
                        "iscrowd": 0,
                    }
                )
                ann_id += 1

    if save_ann_only:
        json.dump(coco_anns, open(save_json, "w"))
    else:
        coco = {
            "images": coco_images,
            "annotations": coco_anns,
            "categories": [{"id": i, "name": str(i)} for i in range(1, 91)],
        }
        json.dump(coco, open(save_json, "w"))
    return save_json

def eval_coco(gt_json, pred_json):
    print(f"==> Loading GT from:   {gt_json}")
    print(f"==> Loading Pred from: {pred_json}")
    coco_gt   = COCO(str(gt_json))
    coco_pred = coco_gt.loadRes(str(pred_json))
    ev = COCOeval(coco_gt, coco_pred, "bbox")
    ev.evaluate(); ev.accumulate(); ev.summarize()

def filesize(path: Path) -> int:
    try:
        return path.stat().st_size
    except Exception:
        return 0

def try_ffprobe_bitrate(path: Path):
    # 尝试读取比特率（可能没有ffprobe，失败则返回None）
    cmd = f'ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of default=nw=1 "{path}"'
    try:
        out = subprocess.check_output(shlex.split(cmd), stderr=subprocess.STDOUT).decode()
        for line in out.splitlines():
            if line.startswith("bit_rate="):
                br = int(line.split("=")[1])
                return br  # bps
    except Exception:
        return None

def compute_compression_metrics(orig_video: Path, roi_video: Path, gt_frames, pred_frames):
    orig_size = filesize(orig_video)
    roi_size  = filesize(roi_video)
    cr_pct = (1 - (roi_size / orig_size)) * 100 if orig_size > 0 else float('nan')

    # 每帧平均体积（仅供参考，受编码方式/帧率影响）
    avg_orig_per_frame = (orig_size / max(1, len(gt_frames)))
    avg_roi_per_frame  = (roi_size  / max(1, len(pred_frames)))
    ffprobe_br_orig = try_ffprobe_bitrate(orig_video)
    ffprobe_br_roi  = try_ffprobe_bitrate(roi_video)

    print("===================================")
    print(f"原始视频大小: {orig_size/1024/1024:.2f} MB")
    print(f"ROI视频大小:  {roi_size/1024/1024:.2f} MB")
    print(f"压缩率(文件):  {cr_pct:.2f}%")
    print(f"平均每帧体积(原): {avg_orig_per_frame/1024:.2f} KB/frame  | 帧数: {len(gt_frames)}")
    print(f"平均每帧体积(ROI): {avg_roi_per_frame/1024:.2f} KB/frame | 帧数: {len(pred_frames)}")
    if ffprobe_br_orig and ffprobe_br_roi:
        br_drop = (1 - ffprobe_br_roi/ffprobe_br_orig) * 100
        print(f"比特率(FFprobe): 原 {ffprobe_br_orig/1e6:.2f} Mbps → ROI {ffprobe_br_roi/1e6:.2f} Mbps  (下降 {br_drop:.2f}%)")
    print("===================================")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="./../weights/yolov5s.pt")
    ap.add_argument("--imgsz", type=int, default=640)
    ap.add_argument("--conf", type=float, default=0.25)
    ap.add_argument("--gt_frames_dir", default="./../dataset/frames", help="复用 detectAndConvert 抽出的原始帧目录")
    ap.add_argument("--orig_video", default="./../dataset/input.mp4")
    ap.add_argument("--pred_video", default="./../dataset/output_mux.mp4", help="ROI编码/抽帧后的mp4")
    ap.add_argument("--work_dir", default="./eval_tmp")
    args = ap.parse_args()

    work_dir = Path(args.work_dir); work_dir.mkdir(exist_ok=True)

    # 模型
    model = YOLO(args.model)

    # A) 直接复用原始帧（不重复抽帧）
    gt_frames = list_frames(Path(args.gt_frames_dir))
    if len(gt_frames) == 0:
        raise RuntimeError(f"GT帧目录为空：{args.gt_frames_dir}，请先运行 detectAndConvert.py --run_extract")

    # B) 仅对 ROI 视频解帧
    roi_frames_dir = work_dir / "roi_frames"
    pred_frames = video_to_frames(Path(args.pred_video), roi_frames_dir)

    # 对齐帧数（若 ROI/抽帧导致数量变化）
    delta = len(gt_frames) - len(pred_frames)
    if delta > 0:
        print(f"[INFO] 帧数不一致：GT={len(gt_frames)}，Pred={len(pred_frames)}。将跳过GT前 {delta} 帧对齐。")
        gt_frames = gt_frames[delta:]
    elif delta < 0:
        print(f"[WARN] Pred帧数多于GT，裁剪Pred末尾 {-delta} 帧。")
        pred_frames = pred_frames[:len(gt_frames)]

    # C) YOLO 推理 → JSON
    gt_json   = frames_to_coco_json(gt_frames,  model, work_dir / "gt.json",   imgsz=args.imgsz, conf=args.conf, save_ann_only=False)
    pred_json = frames_to_coco_json(pred_frames, model, work_dir / "pred.json", imgsz=args.imgsz, conf=args.conf, save_ann_only=True)

    # D) 计算 mAP
    eval_coco(work_dir / "gt.json", work_dir / "pred.json")

    # E) 压缩率/比特率指标
    compute_compression_metrics(Path(args.orig_video), Path(args.pred_video), gt_frames, pred_frames)

if __name__ == "__main__":
    main()
