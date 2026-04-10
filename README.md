# ⚡ E-Component Detector — AI-Powered Circuit Board Analysis

> **Point your phone at any circuit board. Let AI identify every component, read resistor values, and build a searchable scan history — instantly.**

<div align="center">

<img width="1080" height="2400" alt="Screenshot_1772902800" src="https://github.com/user-attachments/assets/9d65fcf8-a073-4e34-9af8-d508baf8353c" />
<img width="1080" height="2400" alt="Screenshot_1772901812" src="https://github.com/user-attachments/assets/c49fb561-bb7d-4839-997b-8c1d0714f39c" />
<img width="1080" height="2400" alt="Screenshot_1772901816" src="https://github.com/user-attachments/assets/f1bf5f19-ddd7-409b-8f5b-0aaf701eb0d9" />

</div>

---

## 📖 Table of Contents

- [What is This?](#-what-is-this)
- [How It Works](#-how-it-works)
- [AI Pipeline](#-ai-pipeline)
- [Features](#-features)
- [Technology Stack](#-technology-stack)
- [Project Structure](#-project-structure)
- [Quick Setup](#-quick-setup)
  - [Backend Setup (Python)](#1-backend-setup-python)
  - [Flutter App Setup](#2-flutter-app-setup)
- [Running the App](#-running-the-app)
- [Detected Components](#-detected-components-22-classes)
- [App Screens](#-app-screens)
- [API Reference](#-api-reference)
- [Troubleshooting](#-troubleshooting)
- [Credits & Architecture](#-system-architecture)

---

## 🤔 What is This?

**E-Component Detector** is a mobile application that uses a dual-AI system to analyze photos of electronic circuit boards:

1. **YOLOv8** — A custom-trained object detection model that finds and draws bounding boxes around every electronic component in the image.
2. **GPT-4o Vision** — OpenAI's multimodal model that visually reads resistor color bands from the cropped component image and returns the exact resistance value (e.g. `4.7kΩ ±5%`).
3. **Tesseract OCR** — Reads text printed on chips and ICs (e.g. `NE555`, `LM358`).

This solves a real problem: identifying unknown components on a circuit board without a schematic. Just take a photo.

---

## ⚙️ How It Works

```
📱 Flutter App
    │
    ├─ 📷 Camera Page   ─── Capture up to 5 multi-angle photos
    │                        with live quality checks (blur / brightness)
    │
    ├─ 🖼️ Gallery Pick  ─── Select 1 or more images from device gallery
    │
    └─► ResultsPage sends image(s) via HTTP multipart POST
               │
               ▼
🐍 Python FastAPI Backend  (port 8000, running on your PC/laptop)
               │
               ├─ 1. YOLOv8 model  →  detects & crops all components
               │
               ├─ 2. For "Resistor" crops:
               │       └─ GPT-4o Vision  →  reads color bands → "4.7kΩ ±5%"
               │
               └─ 3. For "IC / Chip / Voltage Regulator" crops:
                       └─ Tesseract OCR  →  reads chip markings → "NE555"
               │
               ▼
    JSON response: { detections: [{label, bbox, confidence, extra}] }
               │
               ▼
📱 Flutter renders bounding boxes + component list + saves to History
```

---

## 🧠 AI Pipeline

### 1 — Object Detection (YOLOv8)
- Custom-trained `best.pt` model on a labeled dataset of electronic components
- Detects **22 component classes** (see list below)
- Runs locally on the backend server (no cloud needed for detection itself)
- Returns bounding boxes `[x1, y1, x2, y2]` + confidence scores

### 2 — Resistor Value Reading (GPT-4o Vision) ✨
The most impressive part:
- When YOLO finds a `Resistor`, its crop is encoded as a **base64 JPEG**
- Sent to **GPT-4o** with an expert electronics prompt:
  > "Identify each color band left-to-right, calculate the resistance using the standard color code table, return JSON with bands + ohms value"
- GPT-4o returns structured JSON:
  ```json
  {
    "bands": ["brown", "black", "red", "gold"],
    "ohms_pretty": "1kΩ ±5%",
    "ohms": 1000
  }
  ```
- This replaces the previous error-prone K-means color clustering approach

### 3 — IC Marking Reading (Tesseract OCR)
- Cropped IC/Chip images are preprocessed (grayscale + Otsu thresholding)
- Tesseract reads the part number text from the chip surface

### 4 — Multi-Angle Deduplication
When you take **multiple photos** of the same board:
- **ORB feature matching** (backend) clusters the same component seen from different angles
- **Color signature averaging** (Flutter) deduplicates components across images
- Final result shows each unique component once, with its confidence score averaged

---

## ✨ Features

| Feature | Description |
|---|---|
| 💎 **Premium UI/UX** | Frosted glassmorphism design system & dynamic gradients |
| 📷 **Multi-angle capture** | Take up to 5 photos for better accuracy |
| ✂️ **Image cropping** | Crop before sending to isolate the board |
| ⚠️ **Quality checking** | Blur & brightness warnings before upload |
| 🔍 **22-class detection** | Resistors, capacitors, ICs, transistors, LEDs, and more |
| 🎨 **Resistor value reading** | GPT-4o reads color bands → exact Ω value |
| 🔤 **IC text reading** | Tesseract OCR reads chip part numbers |
| 📜 **Scan history** | All scans saved locally with thumbnails |
| 🔎 **History search** | Search by date, resistor value, or IC name |
| 📤 **Share/Export** | Native sharing of formatted text summary and JSON exports |
| 🌙 **Dark / Light mode** | Theme toggle in customized settings |
| 🖼️ **Gallery import** | Pick existing photos from device |
| 🔍 **Zoomable images** | Pinch-to-zoom detection results |

---

## 🛠️ Technology Stack

### Mobile App (Flutter)
| Package | Purpose |
|---|---|
| `flutter` + `dart` | Cross-platform mobile framework |
| `camera` | Live camera preview & capture |
| `image_picker` | Gallery image selection |
| `image_cropper` | User-controlled cropping UI |
| `http` | REST API calls to backend |
| `photo_view` | Pinch-to-zoom image viewing |
| `provider` | State management (theme) |
| `path_provider` | Local file storage |
| `image` | Client-side image quality analysis |

### Backend (Python)
| Package | Purpose |
|---|---|
| `FastAPI` | REST API framework |
| `uvicorn` | ASGI server |
| `ultralytics (YOLOv8)` | Object detection model |
| `openai` | GPT-4o Vision API for resistor values |
| `opencv-python-headless` | Image preprocessing & ORB matching |
| `pytesseract` | OCR for IC text reading |
| `Pillow` | Image loading & conversion |
| `python-dotenv` | API key management via `.env` |

---

## 📁 Project Structure

```
circuit_detector_app/
│
├── 📱 lib/                          # Flutter app source
│   ├── main.dart                    # App entry point, theme setup
│   ├── pages/
│   │   ├── home_page.dart           # Landing screen with 3 action buttons
│   │   ├── camera_page.dart         # Multi-angle camera capture
│   │   ├── results_page.dart        # Detection results with bounding boxes
│   │   ├── history_page.dart        # Scan history browser
│   │   ├── settings_page.dart       # App settings
│   │   └── theme_provider.dart      # Dark/light mode state
│   ├── services/
│   │   ├── api_service.dart         # HTTP client (auto-tries multiple IPs)
│   │   └── tflite_service.dart      # (Reserved for on-device inference)
│   ├── models/
│   │   └── component_result.dart    # Detection result data model
│   └── utils/
│       └── constants.dart           # App-wide constants
│
├── 🐍 backend/                      # Python FastAPI server
│   ├── app.py                       # Main API — YOLO + GPT-4o + OCR
│   ├── requirements.txt             # Python dependencies
│   ├── .env                         # 🔒 API keys (not committed to git)
│   └── weights/
│       └── best.pt                  # YOLOv8 trained model weights
│
├── 📦 assets/
│   ├── images/
│   │   ├── home_page_bg.webp        # Home screen background
│   │   └── circuit_placeholder.png  # Fallback image
│   ├── models/
│   │   └── best_float32.tflite      # TFLite model (for future on-device use)
│   └── labels.txt                   # 22 component class names
│
└── pubspec.yaml                     # Flutter dependencies
```

---

## 🚀 Quick Setup

### Prerequisites
- Flutter SDK (≥ 3.7)
- Python 3.10+
- Tesseract OCR installed → [Download](https://github.com/UB-Mannheim/tesseract/wiki)
- OpenAI API key
- Android phone on the **same Wi-Fi network** as your PC

---

### 1. Backend Setup (Python)

```bash
# Navigate to backend folder
cd "circuit_detector_app/backend"

# Create and activate virtual environment
python -m venv .venv
.venv\Scripts\activate        # Windows
# source .venv/bin/activate   # macOS/Linux

# Install all dependencies
pip install -r requirements.txt
```

#### Configure your API key
Create a file `backend/.env`:
```env
OPENAI_API_KEY=sk-proj-your-key-here
```

> ⚠️ Never commit `.env` to git — it's already in `.gitignore`

#### Start the backend server
```bash
# Make sure .venv is active, then:
python -m uvicorn app:app --reload --host 0.0.0.0 --port 8000
```

You should see:
```
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:8000
```

#### Find your PC's IP address (needed for the phone to connect)
```bash
ipconfig    # Windows
# Look for "IPv4 Address" under your Wi-Fi adapter
# Example: 192.168.1.105
```

---

### 2. Flutter App Setup

```bash
# From the project root
flutter pub get
```

#### Update the backend IP in `lib/services/api_service.dart`
```dart
static const String _primaryBase = "http://YOUR_PC_IP_HERE:8000";
// Example:
static const String _primaryBase = "http://192.168.1.105:8000";
```

#### Run on your Android device
```bash
flutter run
```

Or build APK:
```bash
flutter build apk --release
```

---

## ▶️ Running the App

### Step-by-step workflow

```
1. Start backend server on your PC  →  python -m uvicorn app:app ...
2. Connect phone to same Wi-Fi as PC
3. Open app on phone
4. Tap "Capture Circuit Image"       →  Camera opens
5. Take 1-5 photos of the board     →  Crop each shot
6. Tap "Finish & Analyze"           →  Photos sent to backend
7. Wait ~5-15 seconds               →  AI processes image(s)
8. View results:
   - Bounding boxes on photo
   - Component list with types
   - Resistor values (e.g. "4.7kΩ ±5%")
   - IC part numbers
9. Scan auto-saved to History        →  searchable, exportable
```

---

## 🔌 Detected Components (22 Classes)

| # | Component | Description |
|---|---|---|
| 1 | **Resistor** | Through-hole resistor (value decoded by GPT-4o Vision) |
| 2 | **Resistor SMD** | Surface-mount resistor |
| 3 | **Capacitor_Electrolytic** | Polarized electrolytic capacitor |
| 4 | **Capacitor_Ceramic** | Non-polarized ceramic disc capacitor |
| 5 | **IC** | Integrated circuit (OCR reads part number) |
| 6 | **Chip** | General chip / microcontroller (OCR reads marking) |
| 7 | **Transistor** | BJT/MOSFET transistor |
| 8 | **Diode (through-hole)** | Standard signal or power diode |
| 9 | **Diode_SMD** | Surface-mount diode |
| 10 | **Zener Diode** | Voltage regulation diode |
| 11 | **LED** | Light-emitting diode |
| 12 | **Voltage_Regulator** | Voltage regulator IC (OCR reads marking) |
| 13 | **Inductor** | Coil / choke |
| 14 | **Connector** | Pin header or connector block |
| 15 | **Relay** | Electromagnetic relay |
| 16 | **Switch_Button** | Tactile switch or push button |
| 17 | **Fuse** | Circuit protection fuse |
| 18 | **Display** | LCD or 7-segment display |
| 19 | **Busser** | Piezoelectric buzzer |
| 20 | **Transformer** | Step-up/step-down transformer |
| 21 | **Clock** | Crystal oscillator |
| 22 | **Variable_Resistor** | Potentiometer / trimmer |

---

## 📱 App Screens

### 🏠 Home Screen
The landing page featuring our premium dark circuitry background and three main frosted glass card actions:
- **Capture Circuit Image** → Opens live camera
- **Pick from Gallery** → Select image(s) from device storage
- **View Scan History** → Browse all previous scans

### 📷 Camera Page
- Live camera preview with a **green guide frame** against a blurred glass control panel
- **Quality check** before each photo (Blur/Brightness)
- Automatic **crop UI** after each shot
- Thumbnail strip at the bottom — tap any thumbnail to View, Re-crop, Retake, Delete
- Up to **5 angles** per session

### 🔍 Results Page
- **Annotated image** with green bounding boxes and confidence %
- **Premium Card-based component summary**:
  - 🟡 Resistors with Ω values and visual color-band chips
  - 🔵 ICs with part numbers
  - 🧩 Others (capacitors, diodes, etc.)
- **Native Sharer** — instantly generate and send a formatted text report of found components
- Multi-angle view — shows which component appears in which angle
- Auto-saves to scan history

### 📜 History Page
- Browse all past scans with dynamically rendering thumbnails (Gallery & Camera captures)
- Premium Dismissible tiles to **Swipe to delete**
- **Search & Filter** by: All | Resistors only | ICs only
- **Native Export** — tap the 3-dot menu to export JSON data to any app on your phone

### ⚙️ Settings Page
- Custom glassmorphism layout
- Toggle Dark / Light mode
- Configure ML Confidence Threshold slider
- App version & licenses info

---

## 🌐 API Reference

### `GET /health`
Check if the backend is running.

**Response:**
```json
{ "ok": true, "model": "best.pt" }
```

---

### `POST /detect`
Detect components in a **single image**.

**Request:** `multipart/form-data`
| Field | Type | Description |
|---|---|---|
| `file` | Image file | The circuit board photo |
| `conf` | float (default: 0.25) | Minimum confidence threshold |

**Response:**
```json
{
  "image": { "width": 1920, "height": 1080 },
  "blurred": false,
  "detections": [
    {
      "label": "Resistor",
      "confidence": 0.9133,
      "bbox": [120, 80, 240, 160],
      "extra": {
        "bands": ["brown", "black", "red", "gold"],
        "ohms": 1000,
        "value": "1kΩ ±5%"
      }
    },
    {
      "label": "IC",
      "confidence": 0.8765,
      "bbox": [300, 200, 480, 380],
      "extra": {
        "ocr": "NE555"
      }
    }
  ]
}
```

---

### `POST /detect_multi`
Detect and **cross-match components** across multiple images of the same board.

**Request:** `multipart/form-data`
| Field | Type | Description |
|---|---|---|
| `files` | List of images | 2–5 photos of the same board |
| `conf` | float (default: 0.25) | Confidence threshold |

**Response:**
```json
{
  "image_count": 3,
  "components": [
    {
      "id": "cmp_0",
      "type": "Resistor",
      "views": [
        { "image_index": 0, "bbox": [120, 80, 240, 160] },
        { "image_index": 2, "bbox": [118, 79, 242, 162] }
      ]
    }
  ]
}
```

---

## 🔧 Troubleshooting

### ❌ `ModuleNotFoundError: No module named 'openai'`
This happens when pip installs to the wrong virtual environment.

**Fix:** Always use the full path to the `.venv` Python:
```bash
"D:\FLUTER\mobile app\circuit_detector_app\backend\.venv\Scripts\python.exe" -m pip install openai
```
Then start server with:
```bash
"D:\FLUTER\mobile app\circuit_detector_app\backend\.venv\Scripts\python.exe" -m uvicorn app:app --reload --host 0.0.0.0 --port 8000
```

---

### ❌ App can't connect to backend
- Ensure phone and PC are on the **same Wi-Fi network**
- Check the IP in `api_service.dart` matches your PC's current IP (`ipconfig`)
- Check Windows Firewall allows port `8000`
- Try: `http://YOUR_PC_IP:8000/health` in phone browser

---

### ❌ Tesseract not found (OCR not working for ICs)
Install Tesseract OCR:
- **Windows:** [Download installer](https://github.com/UB-Mannheim/tesseract/wiki)
- Default install path: `C:\Program Files\Tesseract-OCR\tesseract.exe`

---

### ❌ Resistor value shows "unreadable"
- Ensure your `OPENAI_API_KEY` is set in `backend/.env`
- **Verify OpenAI Quota/Billing:** If you get a 429 Insufficient Quota error from OpenAI, the model will gracefully fallback to Tesseract for ICs but Resistors will return "unreadable".
- Check the backend terminal for `[GPT-4o RESISTOR]` log lines
- Try better lighting / hold the phone steady
- Ensure the resistor is clearly visible and not obstructed

---

### ❌ Camera not working on Android
Add camera permissions in `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.CAMERA"/>
```

---

## 🏗️ System Architecture

<img width="2400" height="1394" alt="System-Architecture" src="https://github.com/user-attachments/assets/f4adb1b6-909a-4897-8f33-3c643ed51a81" />

<img width="2400" height="1350" alt="Technology-Stack" src="https://github.com/user-attachments/assets/a30f064a-d152-4235-8de8-3dc911425e7c" />

<img width="2400" height="1350" alt="AIBased-Electronic-Circuit-Component-Detection-Mobile-App" src="https://github.com/user-attachments/assets/ecbea31a-c166-4114-a5b7-0387d029990b" />

---

## 📊 Model Information

| Property | Value |
|---|---|
| Model | YOLOv8 (custom trained) |
| Weights file | `backend/weights/best.pt` |
| Input | RGB image (any resolution) |
| Output | Bounding boxes + class labels + confidence |
| Classes | 22 electronic component types |
| TFLite version | `assets/models/best_float32.tflite` (reserved for on-device) |

---

## 📝 Environment Variables

Create `backend/.env` (never commit this file):

```env
# Required for resistor value reading
OPENAI_API_KEY=sk-proj-...

# Optional: custom Tesseract path (if not in default location)
TESSERACT_CMD=C:\Program Files\Tesseract-OCR\tesseract.exe

# Optional: custom model path
MODEL_PATH=weights/best.pt
```

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes
4. Commit: `git commit -m "Add my feature"`
5. Push: `git push origin feature/my-feature`
6. Open a Pull Request

---

<div align="center">

**Built with ❤️ using Flutter + FastAPI + YOLOv8 + GPT-4o**

*Point. Capture. Identify. — Instantly.*

</div>
