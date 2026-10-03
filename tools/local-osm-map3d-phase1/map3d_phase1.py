from __future__ import annotations

import hashlib
import json
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path

OVERPASS_URLS = (
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass-api.de/api/interpreter',
)
RAIN_META_URL = 'https://api.rainviewer.com/public/weather-maps.json'
CACHE_DIR = Path(r'D:\AppServ\private\osm-phc\map3d-cache')
_CACHE: dict[str, tuple[float, dict]] = {}
_RAIN_CACHE: tuple[float, dict] | None = None
CACHE_TTL_SECONDS = 900
DISK_CACHE_TTL_SECONDS = 86400
RAIN_CACHE_TTL_SECONDS = 300
MAX_SPAN_DEG = 0.09


def _height(tags: dict) -> float:
    raw = str(tags.get('height') or '').strip().lower().replace('meters', '').replace('meter', '').replace('m', '')
    match = re.search(r'\d+(?:\.\d+)?', raw)
    if match:
        return max(2.5, min(80.0, float(match.group(0))))
    try:
        levels = float(tags.get('building:levels') or 0)
    except (TypeError, ValueError):
        levels = 0
    return max(3.5, min(45.0, levels * 3.0 if levels > 0 else 5.5))


def _feature(element: dict):
    geom = element.get('geometry') or []
    coords = []
    for point in geom:
        try:
            coords.append([float(point['lon']), float(point['lat'])])
        except (KeyError, TypeError, ValueError):
            continue
    if len(coords) < 3:
        return None
    if coords[0] != coords[-1]:
        coords.append(coords[0])
    tags = element.get('tags') or {}
    return {
        'type': 'Feature',
        'geometry': {'type': 'Polygon', 'coordinates': [coords]},
        'properties': {
            'osm_id': str(element.get('id') or ''),
            'height': _height(tags),
            'levels': str(tags.get('building:levels') or ''),
            'building': str(tags.get('building') or 'yes'),
        },
    }
def _disk_cache_path(key: str) -> Path:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha256(key.encode('utf-8')).hexdigest()[:24]
    return CACHE_DIR / f'buildings-{digest}.json'


def _read_disk_cache(key: str, max_age: int = DISK_CACHE_TTL_SECONDS) -> dict | None:
    path = _disk_cache_path(key)
    try:
        if not path.exists() or time.time() - path.stat().st_mtime > max_age:
            return None
        data = json.loads(path.read_text(encoding='utf-8'))
        if data.get('type') != 'FeatureCollection':
            return None
        data['cache'] = 'disk'
        return data
    except Exception:
        return None


def _write_disk_cache(key: str, data: dict) -> None:
    try:
        path = _disk_cache_path(key)
        temporary = path.with_suffix('.tmp')
        temporary.write_text(json.dumps(data, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
        temporary.replace(path)
    except Exception:
        pass


def fetch_buildings(south: float, west: float, north: float, east: float) -> dict:
    if not (-90 <= south < north <= 90 and -180 <= west < east <= 180):
        raise ValueError('INVALID_BBOX')
    if (north - south) > MAX_SPAN_DEG or (east - west) > MAX_SPAN_DEG:
        raise ValueError('BBOX_TOO_LARGE')
    key = ','.join(f'{v:.4f}' for v in (south, west, north, east))
    cached = _CACHE.get(key)
    if cached and time.time() - cached[0] < CACHE_TTL_SECONDS:
        return cached[1]
    disk = _read_disk_cache(key)
    if disk:
        _CACHE[key] = (time.time(), disk)
        return disk
    query = (
        '[out:json][timeout:18];'
        f'way["building"]({south:.6f},{west:.6f},{north:.6f},{east:.6f});'
        'out tags geom;'
    )
    encoded = urllib.parse.urlencode({'data': query}).encode('utf-8')
    payload = None
    errors = []
    for endpoint in OVERPASS_URLS:
        try:
            req = urllib.request.Request(
                endpoint,
                data=encoded,
                method='POST',
                headers={'User-Agent': 'PRB-PHC-Local-Map3D/2.1.77'},
            )
            with urllib.request.urlopen(req, timeout=18) as response:
                payload = json.loads(response.read().decode('utf-8'))
            break
        except Exception as exc:
            errors.append(type(exc).__name__)
    if payload is None:
        stale = _read_disk_cache(key, max_age=30 * 86400)
        if stale:
            stale['cache'] = 'stale_disk'
            _CACHE[key] = (time.time(), stale)
            return stale
        raise RuntimeError('OVERPASS_UNAVAILABLE:' + ','.join(errors))
    features = []
    for element in payload.get('elements') or []:
        feature = _feature(element)
        if feature:
            features.append(feature)
    result = {'type': 'FeatureCollection', 'features': features, 'source': 'OpenStreetMap/Overpass', 'cache': 'network'}
    _CACHE[key] = (time.time(), result)
    _write_disk_cache(key, result)
    return result
def fetch_rain_meta() -> dict:
    global _RAIN_CACHE
    now = time.time()
    if _RAIN_CACHE and now - _RAIN_CACHE[0] < RAIN_CACHE_TTL_SECONDS:
        return _RAIN_CACHE[1]
    req = urllib.request.Request(RAIN_META_URL, headers={'User-Agent': 'PRB-PHC-Local-Map3D/2.1.77'})
    with urllib.request.urlopen(req, timeout=10) as response:
        payload = json.loads(response.read().decode('utf-8'))
    past = ((payload.get('radar') or {}).get('past') or [])
    if not past:
        result = {'available': False, 'source': 'RainViewer'}
    else:
        latest = past[-1]
        host = str(payload.get('host') or 'https://tilecache.rainviewer.com').rstrip('/')
        path = str(latest.get('path') or '')
        result = {
            'available': bool(path),
            'source': 'RainViewer',
            'time': int(latest.get('time') or 0),
            'tile_url': host + path + '/256/{z}/{x}/{y}/2/1_1.png',
            'meaning': 'weather_radar_context_not_flood_prediction',
        }
    _RAIN_CACHE = (now, result)
    return result