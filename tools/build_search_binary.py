#!/usr/bin/env python3
"""Convert BSI1 JSONL search data to mmap-friendly BSI2 binary data.

Dependencies:
- Reads world_data/search_index.jsonl produced by build_search_index.py.
- Writes pointer-free little-endian BSI2 consumed by native/gps_search_index.h.
- Appends BSA1 trigram postings for full searchable text plus tagged display-only
  postings so broad locality terms can resolve high-ranking visible-name matches
  without scanning every record that merely contains the locality in a subtitle.
- No runtime/Godot dependency.
"""

from __future__ import annotations

import argparse
import json
import shutil
import struct
import time
from array import array
from pathlib import Path

from gps_search import normalize_search_text

HEADER = struct.Struct("<4sIIIQQ")
RECORD = struct.Struct("<" + "II" * 6 + "II" + "dd")
ACCEL_ENTRY = struct.Struct("<III")
ACCEL_FOOTER = struct.Struct("<4sIIIQQQ")
DISPLAY_TRIGRAM_FLAG = 0x80000000
assert HEADER.size == 32
assert RECORD.size == 72
assert ACCEL_ENTRY.size == 12
assert ACCEL_FOOTER.size == 40


def _encoded(value: object) -> bytes:
    return str(value).encode("utf-8")


def _trigram_key(value: str) -> int:
    if len(value) != 3 or any(ord(char) > 0x7F for char in value):
        raise ValueError(f"invalid normalized trigram: {value!r}")
    encoded = value.encode("ascii")
    return encoded[0] | (encoded[1] << 8) | (encoded[2] << 16)


def _text_trigrams(value: str) -> set[int]:
    normalized = normalize_search_text(value)
    keys: set[int] = set()
    for word in normalized.split():
        if len(word) < 3:
            continue
        for offset in range(len(word) - 2):
            keys.add(_trigram_key(word[offset : offset + 3]))
    return keys


def _record_trigrams(display: str, search_text: str) -> set[int]:
    return _text_trigrams(f"{display} {search_text}")


def _write_accelerator(out, postings_by_key: dict[int, array]) -> tuple[int, int]:
    entries_offset = out.tell()
    ordered_keys = sorted(postings_by_key)
    posting_start = 0
    for key in ordered_keys:
        postings = postings_by_key[key]
        out.write(ACCEL_ENTRY.pack(key, posting_start, len(postings)))
        posting_start += len(postings)

    postings_offset = out.tell()
    for key in ordered_keys:
        postings = postings_by_key[key]
        if struct.pack("=I", 1) != struct.pack("<I", 1):
            postings = array("I", postings)
            postings.byteswap()
        postings.tofile(out)

    footer_offset = out.tell()
    out.write(
        ACCEL_FOOTER.pack(
            b"BSA1",
            ACCEL_ENTRY.size,
            len(ordered_keys),
            posting_start,
            entries_offset,
            postings_offset,
            footer_offset,
        )
    )
    return len(ordered_keys), posting_start


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
    postings_by_key: dict[int, array] = {}
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
                search_text = str(item.get("search", ""))
                values = [
                    _encoded(item.get("id", "")),
                    _encoded(item.get("kind", "")),
                    _encoded(display),
                    _encoded(item.get("subtitle", "")),
                    _encoded(normalize_search_text(display)),
                    _encoded(search_text),
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

                for key in _record_trigrams(display, search_text):
                    postings_by_key.setdefault(key, array("I")).append(actual)
                for key in _text_trigrams(display):
                    postings_by_key.setdefault(key | DISPLAY_TRIGRAM_FLAG, array("I")).append(actual)

                actual += 1
                if actual % 250_000 == 0:
                    print(f"[search-binary] {actual:,}/{count:,} records", flush=True)

            if actual != count:
                raise ValueError(f"BSI1 record count mismatch: header={count} actual={actual}")
            strings.flush()
            with strings_tmp.open("rb") as strings_read:
                shutil.copyfileobj(strings_read, out, length=8 * 1024 * 1024)

            trigram_count, posting_count = _write_accelerator(out, postings_by_key)

        tmp.replace(output)
    finally:
        strings_tmp.unlink(missing_ok=True)
        tmp.unlink(missing_ok=True)

    print(
        f"[search-binary] output: {output} ({output.stat().st_size:,} bytes) | "
        f"records={actual:,} | trigram entries={trigram_count:,} | postings={posting_count:,} | "
        f"{time.monotonic() - started:.1f}s",
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
