#!/usr/bin/env python3
"""Convert BSI1 JSONL search data to mmap-friendly BSI2 binary data.

Dependencies:
- Reads world_data/search_index.jsonl produced by build_search_index.py.
- Writes pointer-free little-endian BSI2 consumed by native/gps_search_index.h.
- No runtime/Godot dependency.
"""

from __future__ import annotations

import argparse
import json
import shutil
import struct
import time
from pathlib import Path

from gps_search import normalize_search_text

HEADER = struct.Struct("<4sIIIQQ")
RECORD = struct.Struct("<" + "II" * 6 + "II" + "dd")
assert HEADER.size == 32
assert RECORD.size == 72


def _encoded(value: object) -> bytes:
    return str(value).encode("utf-8")


def build_search_binary(source: Path, output: Path) -> Path:
    started = time.monotonic()
    if not source.is_file():
        raise FileNotFoundError(source)

    with source.open("r", encoding="utf-8") as handle:
        first = handle.readline()
        if not first:
            raise ValueError("BSI1 search index is empty")
        header = json.loads(first)
        if header.get("format") != "BSI1":
            raise ValueError("expected BSI1 source")
        count = int(header.get("count", -1))
    if count < 0 or count > 0xFFFFFFFF:
        raise ValueError("invalid BSI1 record count")

    output.parent.mkdir(parents=True, exist_ok=True)
    tmp = output.with_suffix(output.suffix + ".tmp")
    strings_tmp = output.with_suffix(output.suffix + ".strings.tmp")
    records_offset = HEADER.size
    strings_offset = records_offset + count * RECORD.size

    actual = 0
    string_pos = 0
    try:
        with source.open("r", encoding="utf-8") as source_handle, \
             tmp.open("wb") as out, strings_tmp.open("wb") as strings:
            source_handle.readline()
            out.write(HEADER.pack(b"BSI2", RECORD.size, count, 0, records_offset, strings_offset))

            for line in source_handle:
                if not line.strip():
                    continue
                item = json.loads(line)
                display = str(item.get("display", ""))
                values = [
                    _encoded(item.get("id", "")),
                    _encoded(item.get("kind", "")),
                    _encoded(display),
                    _encoded(item.get("subtitle", "")),
                    _encoded(normalize_search_text(display)),
                    _encoded(item.get("search", "")),
                ]
                spans: list[int] = []
                for value in values:
                    if string_pos + len(value) > 0xFFFFFFFF:
                        raise ValueError("BSI2 string table exceeds uint32 offset range")
                    spans.extend((string_pos, len(value)))
                    strings.write(value)
                    string_pos += len(value)
                out.write(RECORD.pack(
                    *spans,
                    len(display),
                    0,
                    float(item.get("x", 0.0)),
                    float(item.get("y", 0.0)),
                ))
                actual += 1
                if actual % 250_000 == 0:
                    print(f"[search-binary] {actual:,}/{count:,} records", flush=True)

            if actual != count:
                raise ValueError(f"BSI1 record count mismatch: header={count} actual={actual}")
            strings.flush()
            with strings_tmp.open("rb") as strings_read:
                shutil.copyfileobj(strings_read, out, length=8 * 1024 * 1024)

        tmp.replace(output)
    finally:
        strings_tmp.unlink(missing_ok=True)
        tmp.unlink(missing_ok=True)

    print(
        f"[search-binary] output: {output} ({output.stat().st_size:,} bytes) | "
        f"records={actual:,} | {time.monotonic() - started:.1f}s",
        flush=True,
    )
    return output


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, nargs="?", default=Path("world_data/search_index.jsonl"))
    parser.add_argument("--output", type=Path, default=Path("world_data/search_index.bsi"))
    args = parser.parse_args()
    build_search_binary(args.source, args.output)


if __name__ == "__main__":
    main()
