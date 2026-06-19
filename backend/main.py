"""
AgroSense Backend v5
Modules: Ground Data Collection + Field Analysis
Drive: Owner receives all data (Excel + KML + Photos)
"""
from fastapi import FastAPI, HTTPException, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from typing import List, Optional
import math, os, json, logging, datetime, sqlite3, requests, re, base64, io

app = FastAPI(title="AgroSense API v5")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])
logger = logging.getLogger(__name__)

DB_PATH            = os.environ.get("DB_PATH", "/tmp/agrosense.db")
WEATHER_KEY        = os.environ.get("OPENWEATHER_API_KEY", "")
OWNER_FOLDER_ID    = os.environ.get("OWNER_DRIVE_FOLDER_ID", "")
GEE_PROJECT        = os.environ.get("GEE_PROJECT", "")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

logger.info(f"Startup — OWNER_FOLDER_ID set: {bool(OWNER_FOLDER_ID)}")
logger.info(f"Startup — WEATHER_KEY set: {bool(WEATHER_KEY)}")

# ── Google Drive service account ───────────────────────────────────────────────
drive_service  = None
drive_init_err = ""

def init_drive():
    global drive_service, drive_init_err
    try:
        import google.oauth2.service_account as _sa
        import googleapiclient.discovery as _disc

        sa_json = os.environ.get("GEE_SERVICE_ACCOUNT_JSON", "")
        if not sa_json:
            drive_init_err = "GEE_SERVICE_ACCOUNT_JSON not set"
            logger.warning(f"Drive init: {drive_init_err}")
            return
        if not OWNER_FOLDER_ID:
            drive_init_err = "OWNER_DRIVE_FOLDER_ID not set"
            logger.warning(f"Drive init: {drive_init_err}")
            return

        sa_info = json.loads(sa_json)
        logger.info(f"Drive init: using SA {sa_info.get('client_email','?')}")

        creds = _sa.Credentials.from_service_account_info(
            sa_info,
            scopes=["https://www.googleapis.com/auth/drive.file",
                    "https://www.googleapis.com/auth/drive"])
        svc = _disc.build("drive", "v3", credentials=creds,
                          cache_discovery=False)

        # Test: list folder
        res = svc.files().list(
            q=f"'{OWNER_FOLDER_ID}' in parents and trashed=false",
            fields="files(id)", pageSize=1
        ).execute()

        # Test: write a tiny file directly to owner folder
        from googleapiclient.http import MediaIoBaseUpload
        test_bytes = b"agrosense-init-test"
        meta  = {"name": "_init_test.txt", "parents": [OWNER_FOLDER_ID]}
        media = MediaIoBaseUpload(io.BytesIO(test_bytes), mimetype="text/plain")
        f     = svc.files().create(body=meta, media_body=media,
                                    fields="id").execute()
        # Clean up
        svc.files().delete(fileId=f["id"]).execute()
        logger.info(f"Drive write test passed — file id {f['id'][:8]}")

        drive_service  = svc
        drive_init_err = ""
        logger.info(f"Drive ready — folder {OWNER_FOLDER_ID[:8]}...")

    except Exception as e:
        drive_init_err = str(e)
        drive_service  = None
        logger.error(f"Drive init failed: {type(e).__name__}: {e}")

init_drive()

# ── GEE ────────────────────────────────────────────────────────────────────────
GEE_OK = False
try:
    import ee
    from google.oauth2 import service_account as sa
    sa_json = os.environ.get("GEE_SERVICE_ACCOUNT_JSON", "")
    if sa_json:
        key   = json.loads(sa_json)
        creds = ee.ServiceAccountCredentials(email=key["client_email"], key_data=json.dumps(key))
        ee.Initialize(credentials=creds, project=GEE_PROJECT or None)
    else:
        ee.Initialize(project=GEE_PROJECT) if GEE_PROJECT else ee.Initialize()
    GEE_OK = True
    logger.info("GEE ready")
except Exception as e:
    logger.warning(f"GEE unavailable: {e}")

# ── Database ───────────────────────────────────────────────────────────────────
def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_db()
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS ground_records (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            plot_id       TEXT UNIQUE NOT NULL,
            present_crop  TEXT NOT NULL,
            previous_crop TEXT,
            crop_stage    TEXT,
            irrigation    TEXT,
            soil_type     TEXT,
            phone         TEXT,
            observations  TEXT,
            latitude      REAL,
            longitude     REAL,
            location_name TEXT,
            photo_count   INTEGER DEFAULT 0,
            drive_folder  TEXT,
            created_at    TEXT DEFAULT (datetime('now'))
        );
        CREATE TABLE IF NOT EXISTS field_analyses (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            plot_id       TEXT UNIQUE NOT NULL,
            polygon       TEXT NOT NULL,
            area_acres    REAL,
            area_hectares REAL,
            location_name TEXT,
            phone         TEXT,
            cropland_pct  REAL,
            ndvi_peak     REAL,
            ndvi_peak_month TEXT,
            ndvi_health   TEXT,
            ndvi_series   TEXT,
            sow_early     TEXT,
            sow_peak      TEXT,
            sow_late      TEXT,
            sow_reason    TEXT,
            weather       TEXT,
            drive_folder  TEXT,
            analysed_at   TEXT DEFAULT (datetime('now'))
        );
    """)
    conn.commit()
    conn.close()

init_db()

# ── Helpers ────────────────────────────────────────────────────────────────────
def generate_plot_id(crop: str) -> str:
    now  = datetime.datetime.now()
    crop = re.sub(r'[^a-zA-Z0-9]', '', crop.replace(' ', ''))
    return f"{crop}_{now.strftime('%Y%m%d_%H%M')}"

def centroid(coords):
    return (sum(c[0] for c in coords)/len(coords),
            sum(c[1] for c in coords)/len(coords))

def polygon_area(coords):
    n = len(coords)
    area = 0.0
    for i in range(n):
        j = (i+1) % n
        area += coords[i][1]*coords[j][0]
        area -= coords[j][1]*coords[i][0]
    area = abs(area)/2.0
    sq_km    = area * 111.32 * 111.32 * math.cos(math.radians(coords[0][0]))
    acres    = round(sq_km * 247.105, 2)
    hectares = round(sq_km * 100, 2)
    return acres, hectares

def reverse_geocode(lat, lng) -> str:
    try:
        url = f"https://nominatim.openstreetmap.org/reverse?lat={lat}&lon={lng}&format=json"
        res = requests.get(url, headers={"User-Agent": "AgroSense/5.0"}, timeout=5)
        data = res.json()
        addr = data.get("address", {})
        parts = [addr.get("village") or addr.get("town") or addr.get("city") or "",
                 addr.get("state_district") or addr.get("county") or "",
                 addr.get("state") or ""]
        return ", ".join(p for p in parts if p) or f"{lat:.4f}, {lng:.4f}"
    except:
        return f"{lat:.4f}, {lng:.4f}"

# ── Google Drive helpers ───────────────────────────────────────────────────────
def get_or_create_subfolder(parent_id: str, name: str) -> str:
    if not drive_service:
        return ""
    try:
        q = f"name='{name}' and '{parent_id}' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false"
        res = drive_service.files().list(q=q, fields="files(id)").execute()
        files = res.get("files", [])
        if files:
            return files[0]["id"]
        meta = {"name": name, "mimeType": "application/vnd.google-apps.folder",
                "parents": [parent_id]}
        f = drive_service.files().create(body=meta, fields="id").execute()
        return f["id"]
    except Exception as e:
        logger.error(f"Folder create error: {e}")
        return ""

def upload_to_drive(folder_id: str, filename: str, content: bytes, mime: str) -> str:
    if not drive_service or not folder_id:
        return ""
    try:
        from googleapiclient.http import MediaIoBaseUpload
        meta  = {"name": filename, "parents": [folder_id]}
        media = MediaIoBaseUpload(io.BytesIO(content), mimetype=mime)
        f     = drive_service.files().create(
            body=meta, media_body=media, fields="id").execute()
        logger.info(f"Uploaded {filename} → {f.get('id','')[:8]}...")
        return f.get("id", "")
    except Exception as e:
        logger.error(f"Upload FAILED [{filename}]: {type(e).__name__}: {e}")
        return f"ERROR:{type(e).__name__}:{str(e)[:200]}"

def update_excel(plot_id: str, module: str, row_data: dict):
    """Append row to Records.xlsx in owner Drive root folder"""
    if not drive_service or not OWNER_FOLDER_ID:
        logger.warning(f"Excel update skipped — drive_service={drive_service is not None}")
        return
    try:
        import openpyxl
        FILENAME = "AgroSense_Records.xlsx"
        # Try to find existing file
        q = f"name='{FILENAME}' and '{OWNER_FOLDER_ID}' in parents and trashed=false"
        res = drive_service.files().list(q=q, fields="files(id)").execute()
        files = res.get("files", [])

        wb = openpyxl.Workbook()
        ws = wb.active
        ws.title = "Records"
        headers = ["Plot ID","Module","Present Crop","Previous Crop","Crop Stage",
                   "Irrigation","Soil Type","Latitude","Longitude","Location",
                   "Phone","Observations","Photos","NDVI Peak","NDVI Health",
                   "Sow Early","Sow Peak","Sow Late","Cropland %",
                   "Area (acres)","Area (ha)","Drive Folder","Saved At"]

        if files:
            # Download existing
            file_id = files[0]["id"]
            content = drive_service.files().get_media(fileId=file_id).execute()
            wb = openpyxl.load_workbook(io.BytesIO(content))
            ws = wb.active
            # Delete old file
            drive_service.files().delete(fileId=file_id).execute()
        else:
            ws.append(headers)

        # Append new row
        ws.append([
            plot_id, module,
            row_data.get("present_crop",""), row_data.get("previous_crop",""),
            row_data.get("crop_stage",""), row_data.get("irrigation",""),
            row_data.get("soil_type",""), row_data.get("latitude",""),
            row_data.get("longitude",""), row_data.get("location_name",""),
            row_data.get("phone",""), row_data.get("observations",""),
            row_data.get("photo_count",0), row_data.get("ndvi_peak",""),
            row_data.get("ndvi_health",""), row_data.get("sow_early",""),
            row_data.get("sow_peak",""), row_data.get("sow_late",""),
            row_data.get("cropland_pct",""), row_data.get("area_acres",""),
            row_data.get("area_hectares",""), row_data.get("drive_folder",""),
            datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
        ])

        buf = io.BytesIO()
        wb.save(buf)
        buf.seek(0)
        upload_to_drive(OWNER_FOLDER_ID, FILENAME, buf.read(),
                        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    except Exception as e:
        logger.error(f"Excel update error: {e}")

def generate_ground_kml(record: dict) -> bytes:
    plot_id = record["plot_id"]
    desc = "\n".join([
        f"Present Crop: {record.get('present_crop','')}",
        f"Previous Crop: {record.get('previous_crop','')}",
        f"Crop Stage: {record.get('crop_stage','')}",
        f"Irrigation: {record.get('irrigation','')}",
        f"Soil Type: {record.get('soil_type','')}",
        f"Phone: {record.get('phone','')}",
        f"Observations: {record.get('observations','')}",
        f"Photos: {record.get('photo_count',0)}",
        f"Collected: {record.get('created_at','')}",
    ])
    kml = f"""<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>{plot_id}</name>
    <Placemark>
      <name>{plot_id}</name>
      <description><![CDATA[{desc}]]></description>
      <Point>
        <coordinates>{record.get('longitude',0)},{record.get('latitude',0)},0</coordinates>
      </Point>
    </Placemark>
  </Document>
</kml>"""
    return kml.encode()

def generate_analysis_kml(record: dict, polygon: list) -> bytes:
    plot_id = record["plot_id"]
    coords_str = " ".join(f"{c[1]},{c[0]},0" for c in polygon)
    if polygon:
        coords_str += f" {polygon[0][1]},{polygon[0][0]},0"
    desc = "\n".join([
        f"Area: {record.get('area_acres','')} acres / {record.get('area_hectares','')} ha",
        f"Location: {record.get('location_name','')}",
        f"Cropland: {record.get('cropland_pct','')}%",
        f"NDVI Peak: {record.get('ndvi_peak','')} ({record.get('ndvi_peak_month','')})",
        f"NDVI Health: {record.get('ndvi_health','')}",
        f"Sowing Window: {record.get('sow_early','')} – {record.get('sow_late','')}",
        f"Analysed: {record.get('analysed_at','')}",
    ])
    kml = f"""<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>{plot_id}</name>
    <Style id="fieldStyle">
      <LineStyle><color>ff2d7d32</color><width>3</width></LineStyle>
      <PolyStyle><color>662d7d32</color></PolyStyle>
    </Style>
    <Placemark>
      <name>{plot_id}</name>
      <description><![CDATA[{desc}]]></description>
      <styleUrl>#fieldStyle</styleUrl>
      <Polygon>
        <outerBoundaryIs>
          <LinearRing>
            <coordinates>{coords_str}</coordinates>
          </LinearRing>
        </outerBoundaryIs>
      </Polygon>
    </Placemark>
  </Document>
</kml>"""
    return kml.encode()

# ── GEE functions ──────────────────────────────────────────────────────────────
def get_ndvi_series(coords) -> list:
    lat, lng = centroid(coords)
    if not GEE_OK:
        return _mock_ndvi(lat, lng)
    try:
        polygon = ee.Geometry.Polygon([[[c[1], c[0]] for c in coords]])
        end_d   = datetime.date.today()
        start_d = end_d - datetime.timedelta(days=365)
        results = []
        for m in range(12):
            ms = start_d + datetime.timedelta(days=m*30)
            me = ms + datetime.timedelta(days=30)
            col = (ee.ImageCollection("COPERNICUS/S2_SR_HARMONIZED")
                   .filterBounds(polygon).filterDate(str(ms), str(me))
                   .filter(ee.Filter.lt("CLOUDY_PIXEL_PERCENTAGE", 30))
                   .map(lambda img: img.normalizedDifference(["B8","B4"]).rename("ndvi")))
            if col.size().getInfo() == 0:
                results.append({"month": ms.strftime("%b"), "ndvi": None})
                continue
            val = (col.max().reduceRegion(ee.Reducer.mean(), polygon, 10)
                   .get("ndvi").getInfo())
            results.append({"month": ms.strftime("%b"),
                             "ndvi": round(float(val), 3) if val else None})
        return results
    except Exception as e:
        logger.error(f"NDVI: {e}")
        return _mock_ndvi(lat, lng)

def _mock_ndvi(lat, lng):
    import random
    random.seed(int(abs(lat*100+lng*100)))
    base = [0.12,0.14,0.18,0.22,0.25,0.45,0.68,0.78,0.72,0.48,0.22,0.15]
    end_d   = datetime.date.today()
    start_d = end_d - datetime.timedelta(days=365)
    results = []
    for m in range(12):
        ms   = start_d + datetime.timedelta(days=m*30)
        ndvi = round(base[m] + random.uniform(-0.04, 0.04), 3)
        results.append({"month": ms.strftime("%b"), "ndvi": max(0.05, min(0.95, ndvi))})
    return results

def get_crop_mask(coords) -> dict:
    if not GEE_OK:
        return _mock_crop_mask(coords)
    try:
        polygon = ee.Geometry.Polygon([[[c[1],c[0]] for c in coords]])
        lc = ee.ImageCollection("ESA/WorldCover/v200").first()
        def pct(cls):
            total = lc.gte(0).reduceRegion(ee.Reducer.sum(), polygon, 10).get("Map").getInfo() or 1
            count = lc.eq(cls).reduceRegion(ee.Reducer.sum(), polygon, 10).get("Map").getInfo() or 0
            return round((count/total)*100, 1)
        crop_pct = pct(40)
        return {
            "is_cropland":  crop_pct > 0,
            "crop_pct":     crop_pct,
            "tree_pct":     pct(10),
            "shrub_pct":    pct(20),
            "grass_pct":    pct(30),
            "buildup_pct":  pct(50),
            "water_pct":    pct(80),
            "source":       "ESA WorldCover 10m"
        }
    except Exception as e:
        logger.error(f"CropMask: {e}")
        return _mock_crop_mask(coords)

def _mock_crop_mask(coords):
    lat, lng = centroid(coords)
    s = abs(math.sin(lat*9.898+lng*5.233)*33758.5)
    f = s - int(s)
    crop_pct = round(40+f*55, 1)
    return {
        "is_cropland": crop_pct > 0, "crop_pct": crop_pct,
        "tree_pct": round((100-crop_pct)*0.3, 1),
        "shrub_pct": round((100-crop_pct)*0.4, 1),
        "grass_pct": round((100-crop_pct)*0.2, 1),
        "buildup_pct": round((100-crop_pct)*0.1, 1),
        "water_pct": 0.0, "source": "Simulated"
    }

def get_weather(lat, lng) -> list:
    if not WEATHER_KEY:
        return _mock_weather(lat, lng)
    try:
        url = (f"https://api.openweathermap.org/data/2.5/forecast"
               f"?lat={lat}&lon={lng}&appid={WEATHER_KEY}&units=metric&cnt=56")
        res  = requests.get(url, timeout=10)
        data = res.json()
        daily = {}
        for item in data.get("list", []):
            date = item["dt_txt"][:10]
            if date not in daily:
                daily[date] = {"temps": [], "rain": 0, "desc": "", "icon": ""}
            daily[date]["temps"].append(item["main"]["temp"])
            daily[date]["rain"] += item.get("rain", {}).get("3h", 0)
            if not daily[date]["desc"]:
                daily[date]["desc"] = item["weather"][0]["description"].title()
                daily[date]["icon"] = item["weather"][0]["icon"]
        result = []
        for date, d in list(daily.items())[:7]:
            dt = datetime.datetime.strptime(date, "%Y-%m-%d")
            desc = d["desc"]
            result.append({
                "date": date, "day": dt.strftime("%a"),
                "temp_min": round(min(d["temps"]), 1),
                "temp_max": round(max(d["temps"]), 1),
                "rain_mm":  round(d["rain"], 1),
                "desc":     desc,
                "emoji":    _weather_emoji(desc)
            })
        return result
    except Exception as e:
        logger.error(f"Weather: {e}")
        return _mock_weather(lat, lng)

def _weather_emoji(desc):
    d = desc.lower()
    if "thunder" in d: return "⛈"
    if "rain" in d or "drizzle" in d: return "🌧"
    if "cloud" in d: return "⛅"
    if "clear" in d: return "☀️"
    return "🌤"

def _mock_weather(lat, lng):
    import random
    random.seed(int(abs(lat*10+lng*10)))
    descs = ["Partly Cloudy","Clear Sky","Light Rain","Sunny","Overcast"]
    result = []
    for i in range(7):
        dt   = datetime.date.today() + datetime.timedelta(days=i)
        desc = random.choice(descs)
        rain = round(random.uniform(0,20),1) if "Rain" in desc else 0
        result.append({
            "date": str(dt), "day": dt.strftime("%a"),
            "temp_min": round(22+random.uniform(-3,3),1),
            "temp_max": round(33+random.uniform(-3,5),1),
            "rain_mm": rain, "desc": desc, "emoji": _weather_emoji(desc)
        })
    return result


def compute_sowing_window(ndvi_series: list, rainfall: float, season: str="Kharif", crop_name: str="Rice") -> dict:
    crop_calendar = {
        ("Kharif","Rice"): ("15-Jun","01-Jul","20-Jul"),
        ("Kharif","Maize"): ("20-Jun","05-Jul","20-Jul"),
        ("Kharif","Cotton"): ("10-Jun","25-Jun","15-Jul"),
        ("Kharif","Redgram"): ("20-Jun","10-Jul","30-Jul"),
        ("Rabi","Chickpea"): ("15-Oct","01-Nov","30-Nov"),
        ("Rabi","Wheat"): ("01-Nov","15-Nov","15-Dec"),
    }
    key = (season or "Kharif", crop_name or "Rice")
    early, peak, late = crop_calendar.get(key, ("15-Jun","01-Jul","20-Jul"))
    reliability = "High" if rainfall > 800 else "Moderate" if rainfall > 500 else "Low"
    reason = f"{crop_name} {season} sowing window derived from literature calendar and rainfall suitability. Reliability: {reliability}."
    return {"early": early, "peak": peak, "late": late, "reason": reason, "reliability": reliability}

def get_rainfall(lat, lng) -> float:
    if not GEE_OK:
        s = abs(math.sin(lat*12.9898+lng*78.233)*43758.5453)
        return round(400 + (s - int(s)) * 1400, 1)
    try:
        point = ee.Geometry.Point(lng, lat)
        rain  = (ee.ImageCollection("UCSB-CHG/CHIRPS/DAILY")
                 .filterBounds(point).filterDate("2023-06-01","2024-05-31")
                 .sum().reduceRegion(ee.Reducer.mean(), point, 5000)
                 .get("precipitation").getInfo() or 0)
        return round(float(rain), 1)
    except:
        return 600.0

def ndvi_health_label(peak: float) -> str:
    if peak >= 0.6: return "Good"
    if peak >= 0.4: return "Moderate"
    if peak >= 0.2: return "Sparse"
    return "Poor"

def ndvi_interpretation(series: list, peak: float, peak_month: str) -> str:
    vals = [p["ndvi"] for p in series if p["ndvi"] is not None]
    if not vals: return "Insufficient data."
    recent = vals[-1] if vals else 0
    if recent < peak * 0.5:
        return f"Vegetation peaked in {peak_month} ({peak:.2f}) and is currently declining — typical post-harvest pattern."
    elif recent >= peak * 0.9:
        return f"Vegetation is currently at peak levels ({recent:.2f}) — crop is in active growing phase."
    else:
        return f"Vegetation peaked in {peak_month} ({peak:.2f}) and is at moderate levels. Monitor for stress."

# ── Models ──────────────────────────────────────────────────────────────────────
class GroundSaveRequest(BaseModel):
    present_crop:  str
    previous_crop: Optional[str] = None
    crop_stage:    Optional[str] = None
    irrigation:    Optional[str] = None
    soil_type:     Optional[str] = None
    phone:         Optional[str] = None
    observations:  Optional[str] = None
    latitude:      float
    longitude:     float
    photos:        Optional[List[str]] = []
    plot_id:       Optional[str] = None  # if provided, use existing ID (offline sync)

class CropMaskRequest(BaseModel):
    polygon: List[List[float]]

class AnalysisRunRequest(BaseModel):
    polygon:      List[List[float]]
    location_name: Optional[str] = None
    phone:        Optional[str] = None
    present_crop: Optional[str] = "Field"
    season: Optional[str] = "Kharif"
    crop_name: Optional[str] = None

class AnalysisSaveRequest(BaseModel):
    plot_id: str

# ── Ground Data Endpoints ──────────────────────────────────────────────────────

@app.post("/ground/save")
async def save_ground_record(req: GroundSaveRequest):
    plot_id       = req.plot_id or generate_plot_id(req.present_crop)
    location_name = reverse_geocode(req.latitude, req.longitude)
    photo_count  = len(req.photos or [])

    # Save to DB
    db = get_db()
    db.execute("""
        INSERT INTO ground_records
        (plot_id, present_crop, previous_crop, crop_stage, irrigation,
         soil_type, phone, observations, latitude, longitude,
         location_name, photo_count)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
    """, (plot_id, req.present_crop, req.previous_crop, req.crop_stage,
          req.irrigation, req.soil_type, req.phone, req.observations,
          req.latitude, req.longitude, location_name, photo_count))
    db.commit()
    record = dict(db.execute("SELECT * FROM ground_records WHERE plot_id=?",
                             (plot_id,)).fetchone())
    db.close()

    drive_folder_link = ""

    # Drive upload (async-ish)
    if drive_service and OWNER_FOLDER_ID:
        try:
            # Create fields subfolder
            fields_folder = get_or_create_subfolder(OWNER_FOLDER_ID, "Fields")
            plot_folder   = get_or_create_subfolder(fields_folder, plot_id)

            # Upload photos
            for i, photo_b64 in enumerate(req.photos or []):
                try:
                    photo_bytes = base64.b64decode(photo_b64)
                    fname = f"{plot_id}_{str(i+1).zfill(2)}.jpg"
                    upload_to_drive(plot_folder, fname, photo_bytes, "image/jpeg")
                except Exception as e:
                    logger.error(f"Photo upload {i}: {e}")

            # Upload KML
            kml_bytes = generate_ground_kml(record)
            upload_to_drive(
                plot_folder, f"{plot_id}.kml", kml_bytes, "application/vnd.google-earth.kml+xml")

            # Use folder link directly — webViewLink on files requires public share
            drive_folder_link = f"https://drive.google.com/drive/folders/{plot_folder}" if plot_folder else ""

            # Update Excel
            update_excel(plot_id, "Ground", {
                "present_crop": req.present_crop,
                "previous_crop": req.previous_crop or "",
                "crop_stage": req.crop_stage or "",
                "irrigation": req.irrigation or "",
                "soil_type": req.soil_type or "",
                "latitude": req.latitude,
                "longitude": req.longitude,
                "location_name": location_name,
                "phone": req.phone or "",
                "observations": req.observations or "",
                "photo_count": photo_count,
                "drive_folder": drive_folder_link,
            })

            # Update DB with folder link
            db = get_db()
            db.execute("UPDATE ground_records SET drive_folder=? WHERE plot_id=?",
                       (drive_folder_link, plot_id))
            db.commit()
            db.close()

        except Exception as e:
            logger.error(f"Drive save error: {e}")

    return {
        "plot_id": plot_id,
        "location_name": location_name,
        "drive_folder": drive_folder_link,
        "drive_ok": bool(drive_folder_link),
    }

@app.get("/ground")
def list_ground_records():
    db   = get_db()
    rows = db.execute("SELECT * FROM ground_records ORDER BY created_at DESC").fetchall()
    db.close()
    return [dict(r) for r in rows]

@app.get("/ground/{plot_id}")
def get_ground_record(plot_id: str):
    db  = get_db()
    row = db.execute("SELECT * FROM ground_records WHERE plot_id=?", (plot_id,)).fetchone()
    db.close()
    if not row: raise HTTPException(404, "Not found")
    return dict(row)

@app.delete("/ground/{plot_id}")
def delete_ground_record(plot_id: str):
    db = get_db()
    db.execute("DELETE FROM ground_records WHERE plot_id=?", (plot_id,))
    db.commit(); db.close()
    return {"deleted": True}

# ── Field Analysis Endpoints ───────────────────────────────────────────────────

@app.post("/analysis/check-cropland")
def check_cropland(req: CropMaskRequest):
    return get_crop_mask(req.polygon)

@app.post("/analysis/run")
def run_analysis(req: AnalysisRunRequest):
    polygon  = req.polygon
    lat, lng = centroid(polygon)
    acres, hectares = polygon_area(polygon)
    location = req.location_name or reverse_geocode(lat, lng)
    crop_mask   = get_crop_mask(polygon)
    ndvi_series = get_ndvi_series(polygon)
    weather     = get_weather(lat, lng)
    rainfall    = get_rainfall(lat, lng)

    # NDVI stats
    vals = [p["ndvi"] for p in ndvi_series if p["ndvi"] is not None]
    peak_ndvi  = max(vals) if vals else 0
    peak_month = ndvi_series[[p["ndvi"] for p in ndvi_series].index(peak_ndvi)]["month"] if peak_ndvi in [p["ndvi"] for p in ndvi_series] else "—"
    health     = ndvi_health_label(peak_ndvi)
    interpret  = ndvi_interpretation(ndvi_series, peak_ndvi, peak_month)

    sowing = compute_sowing_window(ndvi_series, rainfall)

    # Weather farming note
    rain_days  = [d for d in weather if d.get("rain_mm", 0) > 5]
    farm_note  = f"Rain expected {', '.join(d['day'] for d in rain_days[:2])} — avoid spraying." if rain_days else "Good conditions for field operations this week."

    plot_id = generate_plot_id(req.present_crop or "Field")

    # Save to DB
    db = get_db()
    db.execute("""
        INSERT OR REPLACE INTO field_analyses
        (plot_id, polygon, area_acres, area_hectares, location_name,
         phone, cropland_pct, ndvi_peak, ndvi_peak_month, ndvi_health,
         ndvi_series, sow_early, sow_peak, sow_late, sow_reason, weather)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    """, (plot_id, json.dumps(polygon), acres, hectares, location,
          req.phone, crop_mask["crop_pct"], peak_ndvi, peak_month, health,
          json.dumps(ndvi_series), sowing["early"], sowing["peak"],
          sowing["late"], sowing["reason"], json.dumps(weather)))
    db.commit()
    db.close()

    return {
        "plot_id":       plot_id,
        "area_acres":    acres,
        "area_hectares": hectares,
        "location_name": location,
        "crop_mask":     crop_mask,
        "ndvi": {
            "series":        ndvi_series,
            "peak":          round(peak_ndvi, 3),
            "peak_month":    peak_month,
            "health":        health,
            "interpretation": interpret,
        },
        "weather":       weather,
        "farm_note":     farm_note,
        "sowing":        sowing,
        "gee":           GEE_OK,
    }

@app.post("/analysis/save-to-drive")
def save_analysis_to_drive(req: AnalysisSaveRequest):
    db  = get_db()
    row = db.execute("SELECT * FROM field_analyses WHERE plot_id=?",
                     (req.plot_id,)).fetchone()
    db.close()
    if not row: raise HTTPException(404, "Analysis not found")
    record  = dict(row)
    polygon = json.loads(record["polygon"])

    drive_folder_link = ""
    if drive_service and OWNER_FOLDER_ID:
        try:
            fields_folder = get_or_create_subfolder(OWNER_FOLDER_ID, "Fields")
            plot_folder   = get_or_create_subfolder(fields_folder, record["plot_id"])
            kml_bytes     = generate_analysis_kml(record, polygon)
            upload_to_drive(
                plot_folder, f"{record['plot_id']}.kml",
                kml_bytes, "application/vnd.google-earth.kml+xml")
            drive_folder_link = f"https://drive.google.com/drive/folders/{plot_folder}" if plot_folder else ""
            update_excel(record["plot_id"], "Analysis", {
                "present_crop":  "",
                "latitude":      record.get("area_acres",""),
                "longitude":     "",
                "location_name": record.get("location_name",""),
                "phone":         record.get("phone",""),
                "ndvi_peak":     record.get("ndvi_peak",""),
                "ndvi_health":   record.get("ndvi_health",""),
                "sow_early":     record.get("sow_early",""),
                "sow_peak":      record.get("sow_peak",""),
                "sow_late":      record.get("sow_late",""),
                "cropland_pct":  record.get("cropland_pct",""),
                "area_acres":    record.get("area_acres",""),
                "area_hectares": record.get("area_hectares",""),
                "drive_folder":  drive_folder_link,
            })
            db = get_db()
            db.execute("UPDATE field_analyses SET drive_folder=? WHERE plot_id=?",
                       (drive_folder_link, record["plot_id"]))
            db.commit(); db.close()
        except Exception as e:
            logger.error(f"Analysis Drive save: {e}")

    return {
        "plot_id":    record["plot_id"],
        "drive_folder": drive_folder_link,
        "drive_ok":   bool(drive_folder_link),
    }

@app.get("/analysis")
def list_analyses():
    db   = get_db()
    rows = db.execute("SELECT * FROM field_analyses ORDER BY analysed_at DESC").fetchall()
    db.close()
    return [dict(r) for r in rows]

@app.get("/analysis/{plot_id}")
def get_analysis(plot_id: str):
    db  = get_db()
    row = db.execute("SELECT * FROM field_analyses WHERE plot_id=?", (plot_id,)).fetchone()
    db.close()
    if not row: raise HTTPException(404, "Not found")
    r = dict(row)
    r["ndvi_series"] = json.loads(r.get("ndvi_series","[]"))
    r["weather"]     = json.loads(r.get("weather","[]"))
    r["polygon"]     = json.loads(r.get("polygon","[]"))
    return r

@app.delete("/analysis/{plot_id}")
def delete_analysis(plot_id: str):
    db = get_db()
    db.execute("DELETE FROM field_analyses WHERE plot_id=?", (plot_id,))
    db.commit(); db.close()
    return {"deleted": True}

@app.get("/health")
def health():
    drive_ok    = False
    folder_ok   = False
    drive_error = drive_init_err

    # Get SA email for confirmation
    sa_email = ""
    try:
        sa_json = os.environ.get("GEE_SERVICE_ACCOUNT_JSON", "")
        if sa_json:
            sa_email = json.loads(sa_json).get("client_email", "")
    except: pass

    if drive_service:
        try:
            drive_service.files().list(
                q=f"'{OWNER_FOLDER_ID}' in parents and trashed=false",
                fields="files(id)", pageSize=1
            ).execute()
            folder_ok = True
            drive_ok  = True
        except Exception as e:
            drive_error = str(e)

    return {
        "status":            "ok",
        "version":           "5.1",
        "gee":               GEE_OK,
        "weather":           bool(WEATHER_KEY),
        "drive_client":      drive_service is not None,
        "drive_folder_set":  bool(OWNER_FOLDER_ID),
        "drive_folder_ok":   folder_ok,
        "drive_ok":          drive_ok,
        "drive_error":       drive_error,
        "sa_email":          sa_email,
        "folder_id_preview": OWNER_FOLDER_ID[:8] + "..." if OWNER_FOLDER_ID else "not set",
    }

@app.get("/drive-test-save")
def drive_test_save():
    """End-to-end test: create folder, upload a file, verify it exists"""
    results = {
        "drive_service": drive_service is not None,
        "folder_id": OWNER_FOLDER_ID[:8] + "..." if OWNER_FOLDER_ID else "not set",
        "steps": []
    }
    if not drive_service:
        results["error"] = f"Drive not initialised: {drive_init_err}"
        return results

    try:
        # Step 1: Create Fields subfolder
        fields_id = get_or_create_subfolder(OWNER_FOLDER_ID, "Fields")
        results["steps"].append({"step": "create Fields folder", "ok": bool(fields_id), "id": fields_id[:8] + "..." if fields_id else ""})
        if not fields_id:
            results["error"] = "Could not create Fields folder"
            return results

        # Step 2: Create plot subfolder
        test_id   = f"TEST_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}"
        plot_id   = get_or_create_subfolder(fields_id, test_id)
        results["steps"].append({"step": "create plot folder", "ok": bool(plot_id), "id": plot_id[:8] + "..." if plot_id else ""})
        if not plot_id:
            results["error"] = "Could not create plot folder"
            return results

        # Step 3: Upload KML
        kml = b"""<?xml version="1.0"?><kml xmlns="http://www.opengis.net/kml/2.2"><Document><name>AgroSense Test</name></Document></kml>"""
        file_id = upload_to_drive(plot_id, f"{test_id}.kml", kml, "application/vnd.google-earth.kml+xml")
        kml_ok = bool(file_id) and not file_id.startswith("ERROR")
        results["steps"].append({"step": "upload KML", "ok": kml_ok, "result": file_id})
        if not kml_ok:
            results["fix"] = "Most likely cause: Google Drive API not enabled in Google Cloud Console. Go to console.cloud.google.com -> APIs & Services -> Enable APIs -> Google Drive API"
            return results

        # Step 4: Upload a tiny test photo
        # 1x1 red pixel JPEG
        jpeg = bytes([0xFF,0xD8,0xFF,0xE0,0x00,0x10,0x4A,0x46,0x49,0x46,0x00,0x01,
                      0x01,0x00,0x00,0x01,0x00,0x01,0x00,0x00,0xFF,0xDB,0x00,0x43,
                      0x00,0x08,0x06,0x06,0x07,0x06,0x05,0x08,0x07,0x07,0x07,0x09,
                      0x09,0x08,0x0A,0x0C,0x14,0x0D,0x0C,0x0B,0x0B,0x0C,0x19,0x12,
                      0x13,0x0F,0x14,0x1D,0x1A,0x1F,0x1E,0x1D,0x1A,0x1C,0x1C,0x20,
                      0x24,0x2E,0x27,0x20,0x22,0x2C,0x23,0x1C,0x1C,0x28,0x37,0x29,
                      0x2C,0x30,0x31,0x34,0x34,0x34,0x1F,0x27,0x39,0x3D,0x38,0x32,
                      0x3C,0x2E,0x33,0x34,0x32,0xFF,0xC0,0x00,0x0B,0x08,0x00,0x01,
                      0x00,0x01,0x01,0x01,0x11,0x00,0xFF,0xC4,0x00,0x1F,0x00,0x00,
                      0x01,0x05,0x01,0x01,0x01,0x01,0x01,0x01,0x00,0x00,0x00,0x00,
                      0x00,0x00,0x00,0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,
                      0x09,0x0A,0x0B,0xFF,0xC4,0x00,0xB5,0x10,0x00,0x02,0x01,0x03,
                      0x03,0x02,0x04,0x03,0x05,0x05,0x04,0x04,0x00,0x00,0x01,0x7D,
                      0x01,0x02,0x03,0x00,0x04,0x11,0x05,0x12,0x21,0x31,0x41,0x06,
                      0x13,0x51,0x61,0x07,0x22,0x71,0x14,0x32,0x81,0x91,0xA1,0x08,
                      0x23,0x42,0xB1,0xC1,0x15,0x52,0xD1,0xF0,0x24,0x33,0x62,0x72,
                      0x82,0x09,0x0A,0x16,0x17,0x18,0x19,0x1A,0x25,0x26,0x27,0x28,
                      0x29,0x2A,0x34,0x35,0x36,0x37,0x38,0x39,0x3A,0x43,0x44,0x45,
                      0xFF,0xDA,0x00,0x08,0x01,0x01,0x00,0x00,0x3F,0x00,0xF8,0x0A,
                      0x28,0xAF,0xFF,0xD9])
        photo_id = upload_to_drive(plot_id, f"{test_id}_01.jpg", jpeg, "image/jpeg")
        photo_ok = bool(photo_id) and not photo_id.startswith("ERROR")
        results["steps"].append({"step": "upload photo", "ok": photo_ok, "result": photo_id})

        # Step 5: Verify files exist
        from googleapiclient.http import MediaIoBaseUpload as _
        res = drive_service.files().list(
            q=f"'{plot_id}' in parents and trashed=false",
            fields="files(id,name)"
        ).execute()
        found = [f["name"] for f in res.get("files", [])]
        results["steps"].append({"step": "verify files in folder", "ok": len(found) > 0, "files": found})
        results["folder_url"] = f"https://drive.google.com/drive/folders/{plot_id}"
        results["success"]    = all(s["ok"] for s in results["steps"])

    except Exception as e:
        results["error"] = str(e)

    return results

