from __future__ import annotations

import json
import re
import time
import urllib.parse
import urllib.request

OVERPASS_URL = 'https://overpass-api.de/api/interpreter'
_CACHE: dict[str, tuple[float, dict]] = {}
CACHE_TTL_SECONDS = 900
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


def fetch_buildings(south: float, west: float, north: float, east: float) -> dict:
    if not (-90 <= south < north <= 90 and -180 <= west < east <= 180):
        raise ValueError('INVALID_BBOX')
    if (north - south) > MAX_SPAN_DEG or (east - west) > MAX_SPAN_DEG:
        raise ValueError('BBOX_TOO_LARGE')
    key = ','.join(f'{v:.4f}' for v in (south, west, north, east))
    cached = _CACHE.get(key)
    if cached and time.time() - cached[0] < CACHE_TTL_SECONDS:
        return cached[1]
    query = (
        '[out:json][timeout:18];'
        f'way["building"]({south:.6f},{west:.6f},{north:.6f},{east:.6f});'
        'out tags geom;'
    )
    req = urllib.request.Request(
        OVERPASS_URL,
        data=urllib.parse.urlencode({'data': query}).encode('utf-8'),
        method='POST',
        headers={'User-Agent': 'PRB-PHC-Local-Map3D/2.1.76'},
    )
    with urllib.request.urlopen(req, timeout=22) as response:
        payload = json.loads(response.read().decode('utf-8'))
    features = []
    for element in payload.get('elements') or []:
        feature = _feature(element)
        if feature:
            features.append(feature)
    result = {'type': 'FeatureCollection', 'features': features, 'source': 'OpenStreetMap/Overpass'}
    _CACHE[key] = (time.time(), result)
    return result