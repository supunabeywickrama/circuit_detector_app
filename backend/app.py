# app.py
import io
import os
import re
import json
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
#   IMAGE UTILS
# --------------------------------------------------
def bgr_to_base64_jpeg(bgr: np.ndarray, max_dim: int = 512, quality: int = 88) -> str:
    """Resize a BGR image and encode as base64 JPEG string."""
    h, w = bgr.shape[:2]
    if max(h, w) > max_dim:
        scale = max_dim / max(h, w)
        bgr = cv2.resize(bgr, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)
    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
    pil_img = Image.fromarray(rgb)
    buf = io.BytesIO()
    pil_img.save(buf, format="JPEG", quality=quality)
    return base64.b64encode(buf.getvalue()).decode("utf-8")


def parse_gpt_json(raw: str) -> dict:
    """Strip markdown fences and parse JSON from a GPT response."""
    cleaned = re.sub(r"```(?:json)?", "", raw).strip().strip("`").strip()
    return json.loads(cleaned)


# --------------------------------------------------
#   BLUR DETECTION  (improved)
# --------------------------------------------------
def compute_blur_variance(bgr: np.ndarray) -> float:
    """
    Return the Laplacian variance of the image.
    Normalised to a fixed analysis size so variance is comparable
    regardless of the original image resolution.
    """
    try:
        g = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
        # Resize to at most 800 px on the longest side for consistent measurement
        h, w = g.shape[:2]
        if max(h, w) > 800:
            scale = 800.0 / max(h, w)
            g = cv2.resize(g, (int(w * scale), int(h * scale)))
        var = float(cv2.Laplacian(g, cv2.CV_64F).var())
        print(f"[BLUR] Laplacian variance: {var:.2f}")
        return var
    except Exception as e:
        print(f"[BLUR] error: {e}")
        return 9999.0   # assume not blurry on error


def is_blurry(bgr: np.ndarray, thresh: float = 80.0) -> bool:
    return compute_blur_variance(bgr) < thresh


# --------------------------------------------------
#   STEP 1 — GPT-4o: Is this a circuit board image?
# --------------------------------------------------
VALIDATION_PROMPT = """\
Look at this image carefully.
Reply ONLY with this exact JSON — nothing else:
{
  "is_circuit": true,
  "reason": "one-sentence explanation"
}

Rules:
- Set "is_circuit" to true ONLY when the image clearly shows a PCB / circuit board
  with visible electronic components (resistors, capacitors, ICs, transistors, LEDs,
  diodes, connectors, traces, etc.).
- Set "is_circuit" to false for everything else: people, food, text documents,
  blank or plain-color images, random objects, screenshots, etc.
- "reason" must be one short sentence.
"""


def validate_circuit_image(bgr: np.ndarray) -> Dict[str, Any]:
    """
    Quick GPT-4o sanity check: does this image actually show circuit components?
    Uses detail='low' for speed and cost efficiency.
    Returns {"is_circuit": bool, "reason": str}
    """
    try:
        b64 = bgr_to_base64_jpeg(bgr, max_dim=512, quality=80)
        response = openai_client.chat.completions.create(
            model="gpt-4o",
            messages=[{
                "role": "user",
                "content": [
                    {"type": "text", "text": VALIDATION_PROMPT},
                    {"type": "image_url", "image_url": {
                        "url": f"data:image/jpeg;base64,{b64}",
                        "detail": "low",
                    }},
                ],
            }],
            max_tokens=80,
            temperature=0,
        )
        raw = response.choices[0].message.content.strip()
        print(f"[VALIDATE] GPT-4o response: {raw}")
        data = parse_gpt_json(raw)
        return {
            "is_circuit": bool(data.get("is_circuit", False)),
            "reason": str(data.get("reason", "Unknown")),
        }
    except Exception as e:
        print(f"[VALIDATE] exception (allowing through): {e}")
        # On API error, allow through — don't block user on validation failure
        return {"is_circuit": True, "reason": "Validation skipped (API error)"}


# --------------------------------------------------
#   STEP 2 — GPT-4o Vision: Read resistor color bands
# --------------------------------------------------
RESISTOR_PROMPT = """\
You are an expert electronics engineer specialising in reading resistor colour bands.

You are given a cropped image of a through-hole resistor.

Task:
1. Identify each colour band on the resistor body, left-to-right (ignore the tolerance
   band on the far right once you have read the others).
2. State the colour of every band clearly.
3. Calculate the resistance value using the standard resistor colour code:
   - 4-band: digit  digit  multiplier  tolerance
   - 5-band: digit  digit  digit  multiplier  tolerance
4. Return the final resistance value in a clean format like "4.7kΩ ±5%".

Important:
- If the image is too blurry, unclear, or not a resistor, say "unreadable".
- Reply ONLY with this exact JSON, nothing else:
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
    Send the resistor crop to GPT-4o Vision and return decoded resistance info.
    Returns dict with keys: bands, ohms_pretty, ohms, band_count — or None.
    """
    try:
        if bgr_crop is None or bgr_crop.size == 0:
            return None

        # Upscale very small crops so GPT can see the bands clearly
        h, w = bgr_crop.shape[:2]
        if max(h, w) < 60:
            scale = 120.0 / max(1, max(h, w))
            bgr_crop = cv2.resize(bgr_crop, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_CUBIC)

        b64 = bgr_to_base64_jpeg(bgr_crop, max_dim=512, quality=92)

        response = openai_client.chat.completions.create(
            model="gpt-4o",
            messages=[{
                "role": "user",
                "content": [
                    {"type": "text", "text": RESISTOR_PROMPT},
                    {"type": "image_url", "image_url": {
                        "url": f"data:image/jpeg;base64,{b64}",
                        "detail": "high",
                    }},
                ],
            }],
            max_tokens=200,
            temperature=0,
        )

        raw = response.choices[0].message.content.strip()
        print(f"[GPT-4o RESISTOR] raw: {raw}")
        data = parse_gpt_json(raw)

        ohms_pretty = data.get("ohms_pretty", "unreadable")
        ohms = data.get("ohms", None)
        bands = data.get("bands", [])

        if ohms_pretty == "unreadable" or ohms is None:
            print("[GPT-4o RESISTOR] unreadable")
            return None

        print(f"[GPT-4o RESISTOR] decoded: {bands} -> {ohms_pretty}")
        return {
            "bands": bands,
            "ohms": float(ohms),
            "ohms_pretty": ohms_pretty,
            "band_count": len(bands),
        }

    except Exception as e:
        print(f"[GPT-4o RESISTOR] exception: {e}")
        return None


# --------------------------------------------------
#   STEP 3 — GPT-4o Vision: Read IC / Chip markings
# --------------------------------------------------
IC_OCR_PROMPT = """\
This is a cropped image of an electronic component — an IC chip, integrated circuit,
microcontroller, voltage regulator, or similar chip package.

Read any text markings visible on the top surface of the component.
Focus on:
- Part number / component identifier (most important)
- Manufacturer prefix if visible
- Package/date codes are secondary

Reply with ONLY the main component identifier as plain text.
Examples of valid replies: "NE555", "LM358N", "ATmega328P", "7805", "L298N", "SN74HC00N"

If absolutely nothing is readable, reply exactly with: unreadable
Do NOT include any explanation, punctuation, or extra text.
"""


def ocr_text_gpt4o(bgr_crop: np.ndarray) -> str:
    """
    Use GPT-4o Vision to read IC/Chip/Voltage Regulator markings.
    Falls back to Tesseract OCR if GPT-4o fails.
    Returns the part number string, or "" if unreadable.
    """
    try:
        if bgr_crop is None or bgr_crop.size == 0:
            return ""

        # Upscale small crops for better readability
        h, w = bgr_crop.shape[:2]
        if max(h, w) < 80:
            scale = 160.0 / max(1, max(h, w))
            bgr_crop = cv2.resize(bgr_crop, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_CUBIC)

        b64 = bgr_to_base64_jpeg(bgr_crop, max_dim=400, quality=92)

        response = openai_client.chat.completions.create(
            model="gpt-4o",
            messages=[{
                "role": "user",
                "content": [
                    {"type": "text", "text": IC_OCR_PROMPT},
                    {"type": "image_url", "image_url": {
                        "url": f"data:image/jpeg;base64,{b64}",
                        "detail": "high",
                    }},
                ],
            }],
            max_tokens=60,
            temperature=0,
        )

        result = response.choices[0].message.content.strip()
        print(f"[GPT-4o IC OCR] result: {result}")

        if result.lower() in ("unreadable", ""):
            return _ocr_tesseract_fallback(bgr_crop)

        return result

    except Exception as e:
        print(f"[GPT-4o IC OCR] exception: {e} — falling back to Tesseract")
        return _ocr_tesseract_fallback(bgr_crop)


def _ocr_tesseract_fallback(bgr_crop: np.ndarray) -> str:
    """Tesseract OCR fallback for IC text reading."""
    try:
        if not shutil.which("tesseract") and not os.path.exists(TES_CMD):
            return ""
        rgb = cv2.cvtColor(bgr_crop, cv2.COLOR_BGR2RGB)
        gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)
        gray = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY | cv2.THRESH_OTSU)[1]
        txt = pytesseract.image_to_string(gray, config="--psm 7")
        result = txt.strip()
        print(f"[Tesseract OCR fallback] result: {result}")
        return result
    except Exception as e:
        print(f"[Tesseract OCR fallback] error: {e}")
        return ""


# --------------------------------------------------
#   API ROUTES
# --------------------------------------------------
@app.get("/health")
def health():
    return {"ok": True, "model": os.path.basename(MODEL_PATH)}


@app.post("/detect")
async def detect(file: UploadFile = File(...), conf: float = 0.25):
    data = await file.read()
    pil = Image.open(io.BytesIO(data)).convert("RGB")
    arr = np.array(pil)
    h_img, w_img = arr.shape[:2]
    bgr = cv2.cvtColor(arr, cv2.COLOR_RGB2BGR)

    # ── STEP 1: Blur check (fast, no API cost) ─────────────────────────────
    blur_var = compute_blur_variance(bgr)
    if blur_var < 80.0:
        return {
            "rejected": True,
            "rejection_type": "blurry",
            "reason": (
                f"Image is too blurry to analyse (sharpness score: {blur_var:.1f}, "
                f"minimum required: 80). Please retake the photo with steady hands "
                f"and good lighting."
            ),
        }

    # ── STEP 2: Circuit validation (GPT-4o, low-detail = cheap & fast) ────
    validation = validate_circuit_image(bgr)
    if not validation["is_circuit"]:
        return {
            "rejected": True,
            "rejection_type": "not_circuit",
            "reason": (
                f"This image does not appear to contain electronic circuit components. "
                f"({validation['reason']}) — Please upload a photo of a PCB or circuit board."
            ),
        }

    # ── STEP 3: YOLO object detection ─────────────────────────────────────
    res = model.predict(arr, conf=conf, verbose=False)[0]
    names = model.names

    detections = []
    for box in res.boxes:
        cls_id = int(box.cls[0])
        cls_name = names[cls_id] if isinstance(names, dict) else str(cls_id)
        confv = float(box.conf[0])
        x1, y1, x2, y2 = map(lambda v: int(round(float(v))), box.xyxy[0].tolist())

        # Clamp to image bounds
        x1 = max(0, min(x1, w_img - 1))
        x2 = max(0, min(x2, w_img - 1))
        y1 = max(0, min(y1, h_img - 1))
        y2 = max(0, min(y2, h_img - 1))
        if x2 <= x1 or y2 <= y1:
            continue

        crop = bgr[y1:y2, x1:x2].copy()
        extra: Dict[str, Any] = {}

        # ── STEP 4a: Resistor → GPT-4o Vision reads colour bands ──────────
        if cls_name == "Resistor":
            extra["value"] = "unreadable"
            try:
                rinfo = resistor_value_from_gpt4o(crop)
                if rinfo:
                    extra["bands"] = rinfo.get("bands")
                    extra["ohms"] = rinfo.get("ohms")
                    extra["value"] = rinfo.get("ohms_pretty")
            except Exception as e:
                print(f"[RESISTOR] decode exception: {e}")

        # ── STEP 4b: IC / Chip / Voltage Reg → GPT-4o Vision reads markings
        if cls_name in ("IC", "Chip", "Voltage_Regulator"):
            try:
                txt = ocr_text_gpt4o(crop)
                if txt:
                    extra["ocr"] = txt
                else:
                    extra["ocr"] = "unreadable"
            except Exception as e:
                print(f"[IC OCR] exception: {e}")
                extra["ocr"] = "unreadable"

        detections.append({
            "label": cls_name,
            "confidence": round(confv, 4),
            "bbox": [x1, y1, x2, y2],
            "extra": extra,
        })

    return {
        "rejected": False,
        "image": {"width": w_img, "height": h_img},
        "blurred": False,   # already rejected above if blurry
        "blur_variance": round(blur_var, 2),
        "detections": detections,
    }


@app.post("/detect_multi")
async def detect_multi(files: list[UploadFile] = File(...), conf: float = 0.25):
    images_bgr = []
    detections_raw = []

    for file in files:
        data = await file.read()
        pil = Image.open(io.BytesIO(data)).convert("RGB")
        arr = np.array(pil)
        bgr = cv2.cvtColor(arr, cv2.COLOR_RGB2BGR)

        # Per-image blur check
        blur_var = compute_blur_variance(bgr)
        if blur_var < 80.0:
            return {
                "rejected": True,
                "rejection_type": "blurry",
                "reason": (
                    f"One of the uploaded images is too blurry (sharpness score: {blur_var:.1f}). "
                    f"Please retake with steady hands and good lighting."
                ),
            }

        images_bgr.append(bgr)
        res = model.predict(arr, conf=conf, verbose=False)[0]
        dets = []
        for box in res.boxes:
            cls_id = int(box.cls[0])
            cls_name = model.names[cls_id]
            x1, y1, x2, y2 = map(int, box.xyxy[0].tolist())
            crop = bgr[y1:y2, x1:x2]
            dets.append({"label": cls_name, "bbox": [x1, y1, x2, y2], "crop": crop})
        detections_raw.append(dets)

    # Validate first image only (cost saving — if it's a circuit board, they all are)
    if images_bgr:
        validation = validate_circuit_image(images_bgr[0])
        if not validation["is_circuit"]:
            return {
                "rejected": True,
                "rejection_type": "not_circuit",
                "reason": (
                    f"The uploaded images do not appear to contain circuit board components. "
                    f"({validation['reason']})"
                ),
            }

    # ORB feature matching across images
    orb = cv2.ORB_create(500)
    for img_dets in detections_raw:
        for det in img_dets:
            kp, des = orb.detectAndCompute(det["crop"], None)
            det["descriptor"] = des
            det["keypoints"] = kp

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
                    if not matches:
                        continue
                    avg_dist = sum(m.distance for m in matches) / len(matches)
                    if avg_dist < 45:
                        cluster.append((o_img_idx, o_det_idx, o_det))
                        used.add((o_img_idx, o_det_idx))

            component_clusters.append(cluster)

    final_components = []
    for comp_id, cluster in enumerate(component_clusters):
        type_label = cluster[0][2]["label"]
        views = [{"image_index": img_idx, "bbox": det["bbox"]} for img_idx, _, det in cluster]
        final_components.append({"id": f"cmp_{comp_id}", "type": type_label, "views": views})

    return {
        "rejected": False,
        "components": final_components,
        "image_count": len(images_bgr),
    }


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
