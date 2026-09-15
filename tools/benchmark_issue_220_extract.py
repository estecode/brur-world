#!/usr/bin/env python3
"""Cold real-Sweden benchmark for only the pyrosm extraction stage of #220.

This intentionally stops after every dumb per-domain extraction file exists on
disk. It does not build BRUR source caches or any runtime world_data outputs.
"""
from __future__ import annotations

import argparse
import json
import shutil
import time
from datetime import datetime, timezone
from pathlib import Path

from pyrosm_source_stage import DOMAINS, extract_source_stage

EXPECTED_SOURCE_SIZE = 814_508_417


def _now() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def _log(message: str) -> None:
    print(f"[{_now()}] [220-extract-benchmark] {message}", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pbf", type=Path)
    parser.add_argument("--output", type=Path, default=Path("/tmp/brur-220-extracted-cache"))
    parser.add_argument("--report", type=Path, default=Path("/tmp/brur-220-extract-benchmark.json"))
    parser.add_argument("--workers", default="auto")
    args = parser.parse_args()

    source = args.pbf.resolve()
    output = args.output.resolve()
    report_path = args.report.resolve()
    if not source.is_file():
        raise SystemExit(f"source missing: {source}")
    if source.stat().st_size != EXPECTED_SOURCE_SIZE:
        raise SystemExit(f"wrong Sweden source size: expected={EXPECTED_SOURCE_SIZE} actual={source.stat().st_size}")
    if output.exists():
        _log(f"REMOVE cold-output={output}")
        shutil.rmtree(output)

    workers: int | str = int(args.workers) if str(args.workers).isdigit() else args.workers
    _log(f"START source={source.name} domains={','.join(DOMAINS)}")
    started = time.monotonic()
    extraction = extract_source_stage(source, output, DOMAINS, workers)
    elapsed = time.monotonic() - started

    missing = [domain for domain in DOMAINS if not (output / f"{domain}.osm.pbf").is_file()]
    total_bytes = sum((output / f"{domain}.osm.pbf").stat().st_size for domain in DOMAINS if (output / f"{domain}.osm.pbf").is_file())
    report = {
        "issue": 220,
        "mode": "extract-only",
        "source": str(source),
        "source_size_bytes": source.stat().st_size,
        "domains": list(DOMAINS),
        "extraction_seconds": round(elapsed, 3),
        "extracted_bytes": total_bytes,
        "output": str(output),
        "missing": missing,
        "stage": extraction,
        "passed": not missing,
        "completed_at": _now(),
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    _log(f"STOP AFTER EXTRACTION elapsed={elapsed:.3f}s bytes={total_bytes:,} output={output}")
    _log(f"REPORT path={report_path}")
    if missing:
        raise SystemExit(f"extraction benchmark failed, missing: {', '.join(missing)}")


if __name__ == "__main__":
    main()
