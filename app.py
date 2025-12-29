# app.py
import io
import os
import shutil
import uvicorn
import numpy as np
import cv2
from PIL import Image
from typing import Optional, Dict, Any, List, Tuple
from fastapi import FastAPI, File, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from ultralytics import YOLO
import pytesseract

# --- Optional: set Tesseract path (Windows install) ---
TES_CMD = os.getenv("TESSERACT_CMD", r"C:\Program Files\Tesseract-OCR\tesseract.exe")
if os.path.exists(TES_CMD):
    pytesseract.pytesseract.tesseract_cmd = TES_CMD

# --- Model load ---
MODEL_PATH = os.getenv("MODEL_PATH", "weights/best.pt")
model = YOLO(MODEL_PATH)

app = FastAPI(title="Circuit Detector API")

# --- CORS ---
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # tighten later for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --------------------------------------------------
#                 UTILITIES
# --------------------------------------------------
def is_blurry(bgr: np.ndarray, thresh: float = 100.0) -> bool:
    try:
        g = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
        return float(cv2.Laplacian(g, cv2.CV_64F).var()) < thresh
    except Exception:
        return False


def ocr_text(bgr_crop: np.ndarray) -> str:
    try:
        if not shutil.which("tesseract") and not os.path.exists(TES_CMD):
            return ""
        rgb = cv2.cvtColor(bgr_crop, cv2.COLOR_BGR2RGB)
        gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)
        gray = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY | cv2.THRESH_OTSU)[1]
        txt = pytesseract.image_to_string(gray, config="--psm 7")
        return txt.strip()
    except Exception as e:
        print(f"[OCR warning] {e}")
        return ""


# --------------------------------------------------
#        Colour maps & prototypes
# --------------------------------------------------
DIGIT_MAP = {
    "black": 0, "brown": 1, "red": 2, "orange": 3, "yellow": 4,
    "green": 5, "blue": 6, "violet": 7, "grey": 8, "gray": 8, "white": 9
}
MULTIPLIER_MAP = {
    "black": 0, "brown": 1, "red": 2, "orange": 3, "yellow": 4,
    "green": 5, "blue": 6, "violet": 7, "grey": 8, "gray": 8, "white": 9,
    "gold": -1, "silver": -2
}
TOLERANCE_MAP = {
    "brown": "±1%", "red": "±2%", "green": "±0.5%", "blue": "±0.25%",
    "violet": "±0.1%", "grey": "±0.05%", "gray": "±0.05%", "gold": "±5%", "silver": "±10%"
}

# LAB prototypes (rough)
COLOR_PROTOTYPES_LAB = {
    "black": np.array([20, 0, 0], dtype=np.float32),
    "brown": np.array([40, 18, 20], dtype=np.float32),
    "red": np.array([50, 60, 40], dtype=np.float32),
    "orange": np.array([68, 45, 65], dtype=np.float32),
    "yellow": np.array([85, -5, 85], dtype=np.float32),
    "green": np.array([55, -45, 35], dtype=np.float32),
    "blue": np.array([45, 25, -50], dtype=np.float32),
    "violet": np.array([45, 40, -20], dtype=np.float32),
    "grey": np.array([60, 0, 0], dtype=np.float32),
    "white": np.array([95, 0, 0], dtype=np.float32),
    "gold": np.array([80, 5, 40], dtype=np.float32),
    "silver": np.array([78, 0, 0], dtype=np.float32),
}


def format_ohms(value: float) -> str:
    if value <= 0:
        return "invalid"
    if value < 1e3:
        return f"{value:.0f}Ω"
    elif value < 1e6:
        return f"{value/1e3:.2g}kΩ"
    elif value < 1e9:
        return f"{value/1e6:.2g}MΩ"
    else:
        return f"{value/1e9:.2g}GΩ"


def decode_bands_to_value(bands: List[str]) -> Optional[Dict[str, Any]]:
    n = len(bands)
    if n < 4:
        return None

    def digit(c: str):
        return DIGIT_MAP.get(c)

    def mult_exp(c: str):
        return MULTIPLIER_MAP.get(c)

    if n == 4:
        d1, d2, mult_col, tol_col = bands
        d1, d2 = digit(d1), digit(d2)
        m = mult_exp(mult_col)
        tol = TOLERANCE_MAP.get(tol_col)
        if d1 is None or d2 is None or m is None:
            return None
        ohms = (d1 * 10 + d2) * (10.0 ** m)
        return {"bands": bands, "ohms": ohms, "ohms_pretty": format_ohms(ohms) + (f" {tol}" if tol else ""), "band_count": 4}

    if n == 5:
        d1, d2, d3, mult_col, tol_col = bands
        d1, d2, d3 = digit(d1), digit(d2), digit(d3)
        m = mult_exp(mult_col)
        tol = TOLERANCE_MAP.get(tol_col)
        if d1 is None or d2 is None or d3 is None or m is None:
            return None
        ohms = (d1 * 100 + d2 * 10 + d3) * (10.0 ** m)
        return {"bands": bands, "ohms": ohms, "ohms_pretty": format_ohms(ohms) + (f" {tol}" if tol else ""), "band_count": 5}

    if n >= 6:
        d1, d2, d3, mult_col, tol_col = bands[:5]
        d1, d2, d3 = digit(d1), digit(d2), digit(d3)
        m = mult_exp(mult_col)
        tol = TOLERANCE_MAP.get(tol_col)
        if d1 is None or d2 is None or d3 is None or m is None:
            return None
        ohms = (d1 * 100 + d2 * 10 + d3) * (10.0 ** m)
        return {"bands": bands, "ohms": ohms, "ohms_pretty": format_ohms(ohms) + (f" {tol}" if tol else ""), "band_count": len(bands)}
    return None


def white_balance_gray_world(bgr: np.ndarray) -> np.ndarray:
    bgr = bgr.astype(np.float32)
    mean_b = np.mean(bgr[:, :, 0])
    mean_g = np.mean(bgr[:, :, 1])
    mean_r = np.mean(bgr[:, :, 2])
    mean_gray = (mean_b + mean_g + mean_r) / 3.0 + 1e-6
    bgr[:, :, 0] *= mean_gray / (mean_b + 1e-6)
    bgr[:, :, 1] *= mean_gray / (mean_g + 1e-6)
    bgr[:, :, 2] *= mean_gray / (mean_r + 1e-6)
    bgr = np.clip(bgr, 0, 255).astype(np.uint8)
    return bgr


def classify_color_combined(center_lab: np.ndarray, center_hsv: Tuple[float, float, float]) -> str:
    best = "unknown"
    bestd = 1e9
    for name, proto in COLOR_PROTOTYPES_LAB.items():
        d = float(np.linalg.norm(center_lab - proto))
        if d < bestd:
            bestd = d
            best = name

    # HSV from OpenCV: H in [0,179], S,V in [0,255]
    h, s, v = center_hsv
    try:
        hue_deg = float(h) * 2.0
    except Exception:
        hue_deg = None
    sat = float(s) / 255.0 if s is not None else 0.0
    val = float(v) / 255.0 if v is not None else 0.0

    # grayscale / low saturation handling
    if sat < 0.12:
        if val < 0.25:
            return "black"
        if val > 0.85:
            return "white"
        return "grey"

    if hue_deg is not None:
        if 10 <= hue_deg <= 35:
            # brown vs orange resolution by lightness
            if val < 0.55:
                return "brown" if best in ("brown", "orange") else best
            return "orange" if best in ("orange", "brown", "red") else "orange"
        if 35 < hue_deg <= 60:
            return "yellow"
        if (hue_deg <= 10) or (hue_deg >= 350):
            return "red"
        if 90 <= hue_deg <= 160:
            return "green"
        if 200 <= hue_deg <= 260:
            return "blue"
        if 260 < hue_deg < 320:
            return "violet"
    return best


# --------------------------------------------------
#        Global prototype extraction (new)
# --------------------------------------------------
def extract_global_color_prototypes(bgr_image: np.ndarray, k_min: int = 3, k_max: int = 6) -> Optional[Dict[str, Any]]:
    """
    Extract kmeans centers from a central horizontal strip of the whole image and
    map them to colour names. Returns dict or None.
    """
    try:
        h, w = bgr_image.shape[:2]
        strip_h = max(8, h // 8)
        y1 = max(0, h // 2 - strip_h // 2)
        y2 = min(h, y1 + strip_h)
        strip = bgr_image[y1:y2, :, :]

        if strip.size == 0 or strip.shape[1] < 10:
            return None

        strip_wb = white_balance_gray_world(strip)
        lab = cv2.cvtColor(strip_wb, cv2.COLOR_BGR2LAB)
        hsv = cv2.cvtColor(strip_wb, cv2.COLOR_BGR2HSV)

        cols = []
        xs = []
        for x in range(strip.shape[1]):
            col_lab = lab[:, x, :].astype(np.float32)
            L = col_lab[:, 0]
            mask = L < 250
            if np.count_nonzero(mask) < max(3, strip.shape[0] // 6):
                continue
            m_lab = np.mean(col_lab[mask], axis=0)
            col_hsv = hsv[:, x, :].astype(np.float32)
            m_hsv = np.mean(col_hsv[mask], axis=0)
            cols.append(np.concatenate([m_lab, [m_hsv[0], m_hsv[1]]]))
            xs.append(x)

        if len(cols) < 6:
            return None

        cols = np.array(cols, dtype=np.float32)
        K = min(k_max, max(k_min, max(3, cols.shape[0] // 30)))
        criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 50, 0.5)
        _ret, labels, centers = cv2.kmeans(cols, K, None, criteria, 8, cv2.KMEANS_PP_CENTERS)

        labels = labels.flatten()
        # centers shape (K, feat_len)
        names = []
        for c in centers:
            lab_c = c[:3]
            h_c = c[3] if c.shape[0] > 3 else 0
            s_c = c[4] if c.shape[0] > 4 else 0
            names.append(classify_color_combined(lab_c.astype(np.float32), (h_c, s_c, 0)))

        unique, counts = np.unique(labels, return_counts=True)
        freq_idx = int(unique[np.argmax(counts)]) if len(unique) > 0 else 0

        print("[GLOBAL] centers names:", names, "freq_idx:", freq_idx)
        return {"centers": centers, "names": names, "freq_idx": int(freq_idx)}
    except Exception as e:
        print("[GLOBAL] exception:", e)
        return None


# --------------------------------------------------
#        Resistor extraction (accepts global prototypes)
# --------------------------------------------------
def resistor_value_from_crop(bgr_crop: np.ndarray, global_protos: Optional[Dict[str, Any]] = None) -> Optional[Dict[str, Any]]:
    """
    Improved per-crop resistor decoder. Returns decoded dictionary or None.
    """
    try:
        if bgr_crop is None or bgr_crop.size == 0:
            return None

        h, w = bgr_crop.shape[:2]
        # upscale small crops for more reliable kmeans
        if max(h, w) < 80:
            scale = 120.0 / max(1.0, max(h, w))
            bgr_crop = cv2.resize(bgr_crop, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_CUBIC)
            h, w = bgr_crop.shape[:2]

        wb = white_balance_gray_world(bgr_crop)
        # denoise a bit
        wb = cv2.fastNlMeansDenoisingColored(wb, None, 6, 6, 7, 21)

        strip_h = max(6, h // 6)
        y1 = max(0, h // 2 - strip_h // 2)
        y2 = min(h, y1 + strip_h)
        strip = wb[y1:y2, :, :]

        if strip.size == 0 or strip.shape[1] < 8:
            return None

        lab_strip = cv2.cvtColor(strip, cv2.COLOR_BGR2LAB)
        hsv_strip = cv2.cvtColor(strip, cv2.COLOR_BGR2HSV)

        cols = []
        xs = []
        for x in range(strip.shape[1]):
            col_lab = lab_strip[:, x, :].astype(np.float32)
            L = col_lab[:, 0]
            mask = L < 250
            if np.count_nonzero(mask) < max(3, strip.shape[0] // 6):
                continue
            m_lab = np.mean(col_lab[mask], axis=0)
            col_hsv = hsv_strip[:, x, :].astype(np.float32)
            m_hsv = np.mean(col_hsv[mask], axis=0)
            cols.append(np.concatenate([m_lab, [m_hsv[0], m_hsv[1]]]))
            xs.append(x)

        if len(cols) < 6:
            print("[RESISTOR] too few columns in crop")
            return None

        cols = np.array(cols, dtype=np.float32)

        K = min(6, max(3, max(3, cols.shape[0] // 20)))
        criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 50, 0.5)
        _ret, labels, centers = cv2.kmeans(cols, K, None, criteria, 8, cv2.KMEANS_PP_CENTERS)

        labels = labels.flatten()
        centers = centers.reshape(-1, centers.shape[-1])  # (K, feat_len)

        # Map centers -> names, using global prototype when available
        crop_center_names = []
        if global_protos:
            gcenters = global_protos["centers"]
            gnames = global_protos["names"]
            # ensure compatible feature lengths (use LAB dims primarily)
            for c in centers:
                lab_c = c[:3]
                # distance on LAB only to be safe
                if gcenters.shape[1] >= 3:
                    dists = np.linalg.norm(gcenters[:, :3] - lab_c, axis=1)
                else:
                    dists = np.linalg.norm(gcenters - lab_c, axis=1)
                gi = int(np.argmin(dists))
                if float(dists[gi]) < 35.0:
                    crop_center_names.append(gnames[gi])
                else:
                    # fallback to per-center classification
                    hsv_c = (c[3] if c.shape[0] > 3 else 0, c[4] if c.shape[0] > 4 else 0, 0)
                    crop_center_names.append(classify_color_combined(lab_c.astype(np.float32), hsv_c))
            print("[RESISTOR] mapped crop centers via global:", crop_center_names)
        else:
            for c in centers:
                lab_c = c[:3]
                hsv_c = (c[3] if c.shape[0] > 3 else 0, c[4] if c.shape[0] > 4 else 0, 0)
                crop_center_names.append(classify_color_combined(lab_c.astype(np.float32), hsv_c))
            print("[RESISTOR] crop centers names:", crop_center_names)

        # Build left-to-right label sequence by column
        seq = []
        for feat in cols:
            dists = np.linalg.norm(centers - feat, axis=1)
            idx = int(np.argmin(dists))
            seq.append(idx)

        # collapse consecutive duplicates
        collapsed = []
        for idx in seq:
            if not collapsed or collapsed[-1] != idx:
                collapsed.append(idx)

        collapsed_names = [crop_center_names[i] for i in collapsed]
        print("[RESISTOR] collapsed (raw):", collapsed_names)

        # identify body color (either from global protos freq_idx or most frequent)
        if global_protos:
            try:
                body_idx = global_protos.get("freq_idx", None)
                body_name = global_protos["names"][body_idx] if body_idx is not None and body_idx < len(global_protos["names"]) else None
            except Exception:
                body_name = None
        else:
            unique, counts = np.unique(collapsed_names, return_counts=True)
            body_name = unique[np.argmax(counts)] if len(unique) > 0 else None

        cleaned = [c for c in collapsed_names if c != body_name and c != "unknown"]
        print("[RESISTOR] cleaned before fallback:", cleaned, "body_name:", body_name)

        # Hue fallback if cleaned too short
        if len(cleaned) < 4:
            hue_seq = []
            mid_row = strip.shape[0] // 2
            for x in range(strip.shape[1]):
                h_, s_, v_ = hsv_strip[mid_row, x, :]
                if s_ < 25:  # skip low-sat pixels
                    continue
                hue_seq.append(int(h_))
            if len(hue_seq) >= 6:
                buckets = []
                for h_ in hue_seq:
                    if 10 <= h_ <= 20:
                        b = "orange"
                    elif 21 <= h_ <= 35:
                        b = "yellow"
                    elif 0 <= h_ <= 7 or h_ >= 170:
                        b = "red"
                    elif 35 < h_ <= 85:
                        b = "green"
                    elif 86 <= h_ <= 140:
                        b = "blue"
                    else:
                        b = "brown"
                    if not buckets or buckets[-1] != b:
                        buckets.append(b)
                cleaned = [c for c in buckets if c != body_name]
                print("[RESISTOR] hue fallback cleaned:", cleaned)

        if len(cleaned) < 4:
            print("[RESISTOR] not enough bands found")
            return None

        if len(cleaned) > 6:
            cleaned = cleaned[:6]

        decoded = decode_bands_to_value(cleaned)
        if decoded is None:
            print("[RESISTOR] decode failed for", cleaned)
            return None

        if not (0.01 <= decoded["ohms"] <= 1e9):
            print("[RESISTOR] ohms out-of-range", decoded["ohms"])
            return None

        print("[RESISTOR] decoded:", decoded["bands"], "->", decoded["ohms_pretty"])
        return decoded
    except Exception as e:
        print("[RESISTOR] exception:", e)
        return None


# --------------------------------------------------
#                 ROUTES
# --------------------------------------------------
@app.get("/health")
def health():
    return {"ok": True, "model": os.path.basename(MODEL_PATH)}


@app.post("/detect")
async def detect(file: UploadFile = File(...), conf: float = 0.25):
    data = await file.read()
    pil = Image.open(io.BytesIO(data)).convert("RGB")
    arr = np.array(pil)
    h, w = arr.shape[:2]
    bgr = cv2.cvtColor(arr, cv2.COLOR_RGB2BGR)

    blurred = is_blurry(bgr)

    # compute global colour prototypes (helps under varying lighting)
    global_protos = extract_global_color_prototypes(bgr)
    if global_protos:
        print("[GLOBAL] prototypes extracted:", global_protos["names"])

    res = model.predict(arr, conf=conf, verbose=False)[0]
    names = model.names

    detections = []
    for box in res.boxes:
        cls_id = int(box.cls[0])
        cls_name = names[cls_id] if isinstance(names, dict) else str(cls_id)
        confv = float(box.conf[0])
        x1, y1, x2, y2 = map(lambda v: int(round(float(v))), box.xyxy[0].tolist())

        # clamp
        x1 = max(0, min(x1, w - 1))
        x2 = max(0, min(x2, w - 1))
        y1 = max(0, min(y1, h - 1))
        y2 = max(0, min(y2, h - 1))
        if x2 <= x1 or y2 <= y1:
            continue

        crop = bgr[y1:y2, x1:x2].copy()
        extra: Dict[str, Any] = {}

        # only decode thru-hole Resistor class (not SMD)
        if cls_name == "Resistor":
            extra["value"] = "unreadable"
            try:
                rinfo = resistor_value_from_crop(crop, global_protos)
                if rinfo:
                    extra["bands"] = rinfo.get("bands")
                    extra["ohms"] = rinfo.get("ohms")
                    extra["value"] = rinfo.get("ohms_pretty")
            except Exception as e:
                print("[RESISTOR] exception while decoding:", e)

        if cls_name in ("IC", "Chip", "Voltage_Regulator"):
            txt = ocr_text(crop)
            if txt:
                extra["ocr"] = txt

        detections.append(
            {"label": cls_name, "confidence": round(confv, 4), "bbox": [x1, y1, x2, y2], "extra": extra}
        )

    return {"image": {"width": w, "height": h}, "blurred": blurred, "detections": detections}

@app.post("/detect_multi")
async def detect_multi(files: list[UploadFile] = File(...), conf: float = 0.25):
    import uuid
    
    images_bgr = []
    detections_raw = []
    
    # Step 1 — Load images + run YOLO
    for file in files:
        data = await file.read()
        pil = Image.open(io.BytesIO(data)).convert("RGB")
        arr = np.array(pil)
        bgr = cv2.cvtColor(arr, cv2.COLOR_RGB2BGR)
        images_bgr.append(bgr)
        
        res = model.predict(arr, conf=conf, verbose=False)[0]
        dets = []
        for box in res.boxes:
            cls_id = int(box.cls[0])
            cls_name = model.names[cls_id]
            x1,y1,x2,y2 = map(int, box.xyxy[0].tolist())
            crop = bgr[y1:y2, x1:x2]

            dets.append({
                "label": cls_name,
                "bbox": [x1,y1,x2,y2],
                "crop": crop
            })
        detections_raw.append(dets)

    # Step 2 — Extract ORB features
    orb = cv2.ORB_create(500)
    for img_dets in detections_raw:
        for det in img_dets:
            kp, des = orb.detectAndCompute(det["crop"], None)
            det["descriptor"] = des
            det["keypoints"] = kp

    # Step 3 — Match components across images
    bf = cv2.BFMatcher(cv2.NORM_HAMMING, crossCheck=True)

    component_clusters = []  # list of lists of detections
    used = set()

    for img_idx, img_dets in enumerate(detections_raw):
        for det_idx, det in enumerate(img_dets):
            if (img_idx, det_idx) in used:
                continue

            # start a new component cluster
            cluster = [(img_idx, det_idx, det)]
            used.add((img_idx, det_idx))

            # match with detections in other images
            for o_img_idx, o_img_dets in enumerate(detections_raw):
                if o_img_idx == img_idx: 
                    continue

                for o_det_idx, o_det in enumerate(o_img_dets):
                    if (o_img_idx, o_det_idx) in used:
                        continue

                    if det["descriptor"] is None or o_det["descriptor"] is None:
                        continue

                    matches = bf.match(det["descriptor"], o_det["descriptor"])
                    if len(matches) == 0:
                        continue

                    # compute average distance
                    avg_dist = sum([m.distance for m in matches]) / len(matches)

                    if avg_dist < 45:  # threshold for "same component"
                        cluster.append((o_img_idx, o_det_idx, o_det))
                        used.add((o_img_idx, o_det_idx))

            component_clusters.append(cluster)

    # Step 4 — Build final output
    final_components = []
    for comp_id, cluster in enumerate(component_clusters):
        views = []
        type_label = cluster[0][2]["label"]

        for img_idx, det_idx, det in cluster:
            views.append({
                "image_index": img_idx,
                "bbox": det["bbox"],
            })

        final_components.append({
            "id": f"cmp_{comp_id}",
            "type": type_label,
            "views": views,
        })

    return {
        "components": final_components,
        "image_count": len(images_bgr)
    }


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
