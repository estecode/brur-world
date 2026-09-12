#!/usr/bin/env python3
"""Verify the production GPS route keeps detailed road geometry through E6/Flädie.

Dependencies:
- Starts the production brur-gps-server against existing Sweden routing runtime data.
- Uses world_common projection conversion only; no Godot, rendering or alternate road graph.
- The scenario routes from E6 north of Flädie onto Fjelievägen toward Lund.
"""

from __future__ import annotations

import argparse
import json
import math
import socket
import subprocess
import time
from pathlib import Path

from world_common import EARTH_RADIUS, project, unproject


START_LON_LAT = (13.06597, 55.73585)
TARGET_LON_LAT = (13.15530, 55.71710)
INTERCHANGE_LON_LAT = (13.08994, 55.72257)
INTERCHANGE_RADIUS_MERCATOR = 1_500.0
MAX_INTERCHANGE_SEGMENT_M = 400.0
MIN_INTERCHANGE_POINTS = 6
MAX_LENGTH_ERROR_FRACTION = 0.03


def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(("127.0.0.1", 0))
        return int(listener.getsockname()[1])


def _haversine_m(a: tuple[float, float], b: tuple[float, float]) -> float:
    lon1, lat1 = map(math.radians, a)
    lon2, lat2 = map(math.radians, b)
    dlon = lon2 - lon1
    dlat = lat2 - lat1
    value = math.sin(dlat / 2.0) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2.0) ** 2
    return 2.0 * EARTH_RADIUS * math.asin(min(1.0, math.sqrt(value)))


def _request_route(server: Path, world_data: Path) -> dict:
    graph = world_data / "routing.brg"
    snap = world_data / "routing_snap.brs"
    port = _free_port()
    process = subprocess.Popen(
        [str(server), str(graph), str(snap), str(port)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        connection: socket.socket | None = None
        deadline = time.monotonic() + 10.0
        while time.monotonic() < deadline:
            if process.poll() is not None:
                stderr = process.stderr.read() if process.stderr else ""
                raise RuntimeError(f"GPS server exited before accepting connections: {stderr}")
            try:
                connection = socket.create_connection(("127.0.0.1", port), timeout=0.25)
                break
            except OSError:
                time.sleep(0.05)
        if connection is None:
            raise RuntimeError("GPS server did not become ready")

        start = project(*START_LON_LAT)
        target = project(*TARGET_LON_LAT)
        request = f"{start[0]} {start[1]} {target[0]} {target[1]} fastest\n"
        with connection:
            connection.sendall(request.encode("utf-8"))
            received = b""
            while b"\n" not in received:
                chunk = connection.recv(65536)
                if not chunk:
                    break
                received += chunk
        if b"\n" not in received:
            raise RuntimeError("GPS server returned no complete response")
        return json.loads(received.split(b"\n", 1)[0].decode("utf-8"))
    finally:
        process.terminate()
        try:
            process.wait(timeout=2.0)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=2.0)


def verify_route(payload: dict) -> dict[str, float | int]:
    if not payload.get("success"):
        raise RuntimeError(f"E6/Flädie route failed: {payload}")
    raw_points = payload.get("points")
    if not isinstance(raw_points, list) or len(raw_points) < 2:
        raise RuntimeError("E6/Flädie route returned fewer than two geometry points")
    points = [(float(value[0]), float(value[1])) for value in raw_points]
    lon_lat = [unproject(x, y) for x, y in points]

    polyline_m = sum(_haversine_m(a, b) for a, b in zip(lon_lat, lon_lat[1:]))
    routed_m = float(payload.get("distance_m", 0.0))
    if routed_m <= 0.0:
        raise RuntimeError("E6/Flädie route returned invalid routing distance")
    length_error = abs(polyline_m - routed_m) / routed_m
    if length_error > MAX_LENGTH_ERROR_FRACTION:
        raise RuntimeError(
            f"serialized route length diverges from routed edges: polyline={polyline_m:.1f}m "
            f"route={routed_m:.1f}m error={length_error:.2%}"
        )

    center = project(*INTERCHANGE_LON_LAT)
    nearby_indices = [
        index
        for index, point in enumerate(points)
        if math.hypot(point[0] - center[0], point[1] - center[1]) <= INTERCHANGE_RADIUS_MERCATOR
    ]
    if len(nearby_indices) < MIN_INTERCHANGE_POINTS:
        raise RuntimeError(
            f"route is under-detailed at E6/Flädie: only {len(nearby_indices)} points near interchange"
        )

    nearby_set = set(nearby_indices)
    local_segments = [
        _haversine_m(lon_lat[index], lon_lat[index + 1])
        for index in range(len(points) - 1)
        if index in nearby_set or index + 1 in nearby_set
    ]
    max_local_segment = max(local_segments, default=float("inf"))
    if max_local_segment > MAX_INTERCHANGE_SEGMENT_M:
        raise RuntimeError(
            f"route shortcuts road geometry at E6/Flädie: local segment={max_local_segment:.1f}m "
            f"> {MAX_INTERCHANGE_SEGMENT_M:.0f}m"
        )

    return {
        "points": len(points),
        "nearby_points": len(nearby_indices),
        "route_m": routed_m,
        "polyline_m": polyline_m,
        "length_error_fraction": length_error,
        "max_interchange_segment_m": max_local_segment,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("world_data", type=Path)
    parser.add_argument("server", type=Path)
    args = parser.parse_args()
    world_data = args.world_data.resolve()
    server = args.server.resolve()
    if not server.is_file():
        raise SystemExit(f"missing GPS server: {server}")
    report = verify_route(_request_route(server, world_data))
    print(
        "E6_BJARRED_ROUTE=OK "
        f"points={report['points']} nearby={report['nearby_points']} "
        f"route={report['route_m']:.1f}m polyline={report['polyline_m']:.1f}m "
        f"length_error={report['length_error_fraction']:.2%} "
        f"max_interchange_segment={report['max_interchange_segment_m']:.1f}m"
    )


if __name__ == "__main__":
    main()
