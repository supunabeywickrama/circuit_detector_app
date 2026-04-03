# app.py
import io
import os
import base64
import shutil
import uvicorn
import numpy as np
import cv2
from PIL import Image
from typing import Optional, Dict, Any, List
from fastapi import FastAPI, File, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from ultralytics import YOLO
import pytesseract
from openai import OpenAI
from dotenv import load_dotenv

# --- Load environment variables ---
load_dotenv()

# --- Optional: set Tesseract path (Windows install) ---
TES_CMD = os.getenv("TESSERACT_CMD", r"C:\Program Files\Tesseract-OCR\tesseract.exe")
if os.path.exists(TES_CMD):
    pytesseract.pytesseract.tesseract_cmd = TES_CMD

# --- OpenAI client ---
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
if not OPENAI_API_KEY:
    print("[WARNING] OPENAI_API_KEY is not set in environment or .env file.")

openai_client = OpenAI(api_key=OPENAI_API_KEY)

# --- Model load ---
MODEL_PATH = os.getenv("MODEL_PATH", "weights/best.pt")
model = YOLO(MODEL_PATH)

app = FastAPI(title="Circuit Detector API")

# --- CORS ---
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
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


def bgr_crop_to_base64_jpeg(bgr_crop: np.ndarray, max_dim: int = 400) -> str:
    """Resize crop to a reasonable size and encode as base64 JPEG string."""
    h, w = bgr_crop.shape[:2]
    if max(h, w) > max_dim:
        scale = max_dim / max(h, w)
        bgr_crop = cv2.resize(bgr_crop, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)
    # BGR -> RGB -> PIL -> JPEG bytes -> base64
    rgb = cv2.cvtColor(bgr_crop, cv2.COLOR_BGR2RGB)
    pil_img = Image.fromarray(rgb)
    buf = io.BytesIO()
    pil_img.save(buf, format="JPEG", quality=90)
    return base64.b64encode(buf.getvalue()).decode("utf-8")


# --------------------------------------------------
#        GPT-4o Vision — Resistor value reader
# --------------------------------------------------
RESISTOR_PROMPT = """You are an expert electronics engineer specializing in reading resistor color bands.

You are given a cropped image of a through-hole resistor.

Your task:
1. Identify each color band on the resistor body from left to right (ignore the gold/silver tolerance band on the far right only after reading the other bands).
2. State the color of every band clearly.
3. Calculate the resistance value using the standard resistor color code:
   - 4-band: digit digit multiplier tolerance
   - 5-band: digit digit digit multiplier tolerance
4. Return the final resistance value in a clean format like:
   - "4.7kΩ ±5%" or "220Ω ±5%" or "1MΩ ±1%"

IMPORTANT:
- If the image is too blurry or unclear, say "unreadable".
- Reply ONLY in this exact JSON format, nothing else:
{
  "bands": ["color1", "color2", "color3", "color4"],
  "ohms_pretty": "4.7kΩ ±5%",
  "ohms": 4700
}

If unreadable:
{"bands": [], "ohms_pretty": "unreadable", "ohms": null}
"""


def resistor_value_from_gpt4o(bgr_crop: np.ndarray) -> Optional[Dict[str, Any]]:
    """
    Send the resistor crop to GPT-4o Vision and extract the resistance value.
    Returns a dict with keys: bands, ohms_pretty, ohms  — or None on failure.
    """
    try:
        if bgr_crop is None or bgr_crop.size == 0:
            return None

        # Upscale very small crops so GPT can see the bands
        h, w = bgr_crop.shape[:2]
        if max(h, w) < 60:
            scale = 120.0 / max(1, max(h, w))
            bgr_crop = cv2.resize(bgr_crop, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_CUBIC)

        b64 = bgr_crop_to_base64_jpeg(bgr_crop, max_dim=512)

        response = openai_client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": RESISTOR_PROMPT},
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:image/jpeg;base64,{b64}",
                                "detail": "high",
                            },
                        },
                    ],
                }
            ],
            max_tokens=300,
            temperature=0,
        )

        raw = response.choices[0].message.content.strip()
        print(f"[GPT-4o RESISTOR] raw response: {raw}")

        # Parse JSON from GPT response
        import json, re
        # Strip markdown code fences if present
        cleaned = re.sub(r"```(?:json)?", "", raw).strip().strip("`").strip()
        data = json.loads(cleaned)

        bands = data.get("bands", [])
        ohms_pretty = data.get("ohms_pretty", "unreadable")
        ohms = data.get("ohms", None)

        if ohms_pretty == "unreadable" or ohms is None:
            print("[GPT-4o RESISTOR] unreadable response")
            return None

        print(f"[GPT-4o RESISTOR] decoded: {bands} -> {ohms_pretty}")
        return {
            "bands": bands,
            "ohms": float(ohms) if ohms is not None else None,
            "ohms_pretty": ohms_pretty,
            "band_count": len(bands),
        }

    except Exception as e:
        print(f"[GPT-4o RESISTOR] exception: {e}")
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

        # --- Resistor: GPT-4o Vision reads the color bands ---
        if cls_name == "Resistor":
            extra["value"] = "unreadable"
            try:
                rinfo = resistor_value_from_gpt4o(crop)
                if rinfo:
                    extra["bands"] = rinfo.get("bands")
                    extra["ohms"] = rinfo.get("ohms")
                    extra["value"] = rinfo.get("ohms_pretty")
            except Exception as e:
                print(f"[RESISTOR GPT-4o] exception while decoding: {e}")

        # --- IC / Chip / Voltage Regulator: OCR ---
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
            x1, y1, x2, y2 = map(int, box.xyxy[0].tolist())
            crop = bgr[y1:y2, x1:x2]

            dets.append({
                "label": cls_name,
                "bbox": [x1, y1, x2, y2],
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

    component_clusters = []
    used = set()

    for img_idx, img_dets in enumerate(detections_raw):
        for det_idx, det in enumerate(img_dets):
            if (img_idx, det_idx) in used:
                continue

            cluster = [(img_idx, det_idx, det)]
            used.add((img_idx, det_idx))

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

                    avg_dist = sum([m.distance for m in matches]) / len(matches)

                    if avg_dist < 45:
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
