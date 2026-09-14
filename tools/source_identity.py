"""Cache identity metadata for expensive offline source-derived datasets.

Dependencies:
- Uses only standard-library hashing and JSON file IO.
- Does not depend on OSM parsing, Godot, rendering, or runtime systems.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
from typing import Callable

HASH_ALGORITHM = "sha256"
CHUNK_SIZE = 1024 * 1024
IDENTITY_CACHE_VERSION = 1


def _file_metadata(path: Path) -> dict[str, int]:
    stat = path.stat()
    return {
        "device": int(getattr(stat, "st_dev", 0)),
        "inode": int(getattr(stat, "st_ino", 0)),
        "size_bytes": int(stat.st_size),
        "mtime_ns": int(stat.st_mtime_ns),
        "ctime_ns": int(getattr(stat, "st_ctime_ns", 0)),
    }


def _load_identity_cache(path: Path) -> dict:
    if not path.is_file():
        return {}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return value if isinstance(value, dict) else {}


def _atomic_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + f".tmp-{os.getpid()}")
    temp.write_text(json.dumps(value, indent=2, sort_keys=True), encoding="utf-8")
    temp.replace(path)


def compute_source_identity(path: Path, cache_path: Path | None = None) -> dict[str, object]:
    """Return exact SHA256 + size, reusing only a previously verified digest.

    Strong local file metadata is only a shortcut to an exact digest already
    computed earlier. Any metadata mismatch or corrupt cache forces a full hash.
    """
    if not path.is_file():
        raise FileNotFoundError(path)

    metadata = _file_metadata(path)
    if cache_path is not None:
        cached = _load_identity_cache(cache_path)
        identity = cached.get("identity")
        if (
            cached.get("version") == IDENTITY_CACHE_VERSION
            and cached.get("metadata") == metadata
            and isinstance(identity, dict)
            and identity.get("algorithm") == HASH_ALGORITHM
            and isinstance(identity.get("digest"), str)
            and len(str(identity.get("digest"))) == 64
            and identity.get("size_bytes") == metadata["size_bytes"]
        ):
            return dict(identity)

    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(CHUNK_SIZE):
            digest.update(chunk)

    identity = {
        "algorithm": HASH_ALGORITHM,
        "digest": digest.hexdigest(),
        "size_bytes": metadata["size_bytes"],
    }
    if cache_path is not None:
        _atomic_json(cache_path, {
            "version": IDENTITY_CACHE_VERSION,
            "metadata": metadata,
            "identity": identity,
        })
    return identity


def load_manifest(path: Path) -> dict:
    """Load a JSON manifest, failing closed to an empty manifest on corruption."""
    if not path.is_file():
        return {}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return value if isinstance(value, dict) else {}


def source_identity_matches(entry: object, identity: dict[str, object]) -> bool:
    """Return whether a manifest dataset entry refers to exactly this source identity."""
    if not isinstance(entry, dict):
        return False
    source = entry.get("source")
    if not isinstance(source, dict):
        return False
    return (
        source.get("algorithm") == identity.get("algorithm")
        and source.get("digest") == identity.get("digest")
        and source.get("size_bytes") == identity.get("size_bytes")
    )


def reusable_output(
    manifest_path: Path,
    dataset_key: str,
    identity: dict[str, object],
    output_path: Path,
    validator: Callable[[Path], object],
) -> object | None:
    """Return validated cached output when both source identity and output are valid."""
    manifest = load_manifest(manifest_path)
    if not source_identity_matches(manifest.get(dataset_key), identity):
        return None
    if not output_path.is_file():
        return None
    try:
        return validator(output_path)
    except (OSError, ValueError, TypeError, KeyError, json.JSONDecodeError):
        return None


def write_manifest_entry(manifest_path: Path, dataset_key: str, entry: dict) -> None:
    """Merge one dataset entry into the inspectable world-data manifest."""
    manifest = load_manifest(manifest_path)
    manifest[dataset_key] = entry
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
