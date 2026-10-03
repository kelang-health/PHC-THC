from __future__ import annotations

import hashlib
import math
from functools import lru_cache

FORCE_DISTANCE_KM = 20.0

from .boundary_quality import (
    load_snapshot,
    load_tambon_boundary,
    normalize_community,
    _point_in_geometry,
)


def _outer_ring(geometry: dict):
    kind = geometry.get("type")
    coords = geometry.get("coordinates") or []
    if kind == "Polygon" and coords:
        return coords[0]
    if kind == "MultiPolygon" and coords and coords[0]:
        return coords[0][0]
    return []


def _polygon_centroid(ring):
    pts = [(float(p[0]), float(p[1])) for p in ring if isinstance(p, (list, tuple)) and len(p) >= 2]
    if len(pts) < 3:
        return None
    if pts[0] != pts[-1]:
        pts.append(pts[0])
    area2 = cx = cy = 0.0
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        cross = x0 * y1 - x1 * y0
        area2 += cross
        cx += (x0 + x1) * cross
        cy += (y0 + y1) * cross
    if abs(area2) < 1e-15:
        xs = [p[0] for p in pts[:-1]]
        ys = [p[1] for p in pts[:-1]]
        return (sum(xs) / len(xs), sum(ys) / len(ys))
    return (cx / (3.0 * area2), cy / (3.0 * area2))


def _interior_anchor(geometry: dict):
    ring = _outer_ring(geometry)
    if not ring:
        return None
    centroid = _polygon_centroid(ring)
    if centroid and _point_in_geometry(centroid[0], centroid[1], geometry):
        return centroid
    xs = [float(p[0]) for p in ring if len(p) >= 2]
    ys = [float(p[1]) for p in ring if len(p) >= 2]
    if not xs or not ys:
        return None
    west, east, south, north = min(xs), max(xs), min(ys), max(ys)
    cx, cy = (west + east) / 2.0, (south + north) / 2.0
    candidates = []
    for gy in range(1, 12):
        for gx in range(1, 12):
            x = west + (east - west) * gx / 12.0
            y = south + (north - south) * gy / 12.0
            candidates.append(((x - cx) ** 2 + (y - cy) ** 2, x, y))
    for _, x, y in sorted(candidates):
        if _point_in_geometry(x, y, geometry):
            return (x, y)
    for p in ring:
        x, y = float(p[0]), float(p[1])
        px, py = (x * 0.85 + cx * 0.15), (y * 0.85 + cy * 0.15)
        if _point_in_geometry(px, py, geometry):
            return (px, py)
    return None


def _jitter_inside(anchor, geometry: dict, seed: str):
    ring = _outer_ring(geometry)
    if not ring:
        return anchor
    xs = [float(p[0]) for p in ring if len(p) >= 2]
    ys = [float(p[1]) for p in ring if len(p) >= 2]
    span = max(0.00015, min(max(xs) - min(xs), max(ys) - min(ys)))
    digest = hashlib.sha256(seed.encode("utf-8")).digest()
    angle = (int.from_bytes(digest[:2], "big") / 65535.0) * math.tau
    fraction = 0.05 + (digest[2] / 255.0) * 0.13
    radius = span * fraction
    for scale in (1.0, 0.7, 0.45, 0.25, 0.1):
        x = anchor[0] + math.cos(angle) * radius * scale
        y = anchor[1] + math.sin(angle) * radius * scale
        if _point_in_geometry(x, y, geometry):
            return (x, y)
    return anchor


@lru_cache(maxsize=1)
def _geometry_index():
    communities = {}
    for feature in load_snapshot().get("features", []):
        name = str((feature.get("properties") or {}).get("name") or "").strip()
        geometry = feature.get("geometry") or {}
        if name and geometry:
            communities[normalize_community(name)] = {"name": name, "geometry": geometry}
    tambon = (load_tambon_boundary().get("features") or [])[0].get("geometry") or {}
    return communities, tambon


def _distance_km(lat1, lon1, lat2, lon2):
    radius = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2.0) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2.0) ** 2
    return 2.0 * radius * math.atan2(math.sqrt(a), math.sqrt(max(0.0, 1.0 - a)))


def guarded_display_coordinate(*, house_id, hcode, community, latitude, longitude):
    try:
        lat, lon = float(latitude), float(longitude)
    except (TypeError, ValueError):
        return {"latitude": latitude, "longitude": longitude, "forced_display": False, "force_reason": ""}
    communities, tambon = _geometry_index()
    if tambon and _point_in_geometry(lon, lat, tambon):
        return {"latitude": lat, "longitude": lon, "forced_display": False, "force_reason": ""}
    item = communities.get(normalize_community(community))
    if not item:
        return {
            "latitude": lat, "longitude": lon, "forced_display": False,
            "force_reason": "outside_tambon_no_community_polygon",
        }
    anchor = _interior_anchor(item["geometry"])
    if not anchor:
        return {
            "latitude": lat, "longitude": lon, "forced_display": False,
            "force_reason": "outside_tambon_no_safe_anchor",
        }
    distance_km = _distance_km(lat, lon, anchor[1], anchor[0])
    if distance_km < FORCE_DISTANCE_KM:
        return {
            "latitude": lat, "longitude": lon, "forced_display": False,
            "force_reason": "outside_tambon_near_boundary_not_forced",
            "distance_to_community_km": round(distance_km, 2),
        }
    display_lon, display_lat = _jitter_inside(anchor, item["geometry"], f"{house_id}|{hcode}|{community}")
    return {
        "latitude": display_lat,
        "longitude": display_lon,
        "forced_display": True,
        "force_reason": "outside_tambon_forced_inside_own_community",
        "original_latitude": lat,
        "original_longitude": lon,
        "forced_community": item["name"],
        "distance_to_community_km": round(distance_km, 2),
    }