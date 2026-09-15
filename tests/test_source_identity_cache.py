"""Verify exact SHA identity reuse is metadata-gated and fail-closed."""

from __future__ import annotations

import hashlib
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT=Path(__file__).resolve().parents[1]
TOOLS=ROOT/"tools"
if str(TOOLS) not in sys.path: sys.path.insert(0,str(TOOLS))
import source_identity  # noqa: E402

class Tests(unittest.TestCase):
    def test_warm_metadata_match_reuses_previously_verified_digest(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp); source=root/"source.bin"; source.write_bytes(b"abc"*100); cache=root/"identity.json"
            first=source_identity.compute_source_identity(source,cache)
            with mock.patch.object(hashlib,"sha256",side_effect=AssertionError("unexpected rehash")):
                second=source_identity.compute_source_identity(source,cache)
            self.assertEqual(first,second)

    def test_metadata_change_forces_exact_rehash(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp); source=root/"source.bin"; source.write_bytes(b"abc"); cache=root/"identity.json"
            first=source_identity.compute_source_identity(source,cache)
            source.write_bytes(b"abd")
            second=source_identity.compute_source_identity(source,cache)
            self.assertNotEqual(first["digest"],second["digest"])
            self.assertEqual(second["digest"],hashlib.sha256(b"abd").hexdigest())

    def test_corrupt_identity_cache_fails_closed_to_rehash(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp); source=root/"source.bin"; source.write_bytes(b"abc"); cache=root/"identity.json"; cache.write_text("not-json",encoding="utf-8")
            identity=source_identity.compute_source_identity(source,cache)
            self.assertEqual(identity["digest"],hashlib.sha256(b"abc").hexdigest())

if __name__=="__main__": unittest.main()
