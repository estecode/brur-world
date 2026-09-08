"""Search compact offline address and POI records for GPS destinations.

Dependencies:
- Pure Python; consumes already-built search records from offline tools.
- Returns plain result data only; it owns no map-marker visibility, UI, or routing.
"""

from __future__ import annotations

import json
import re
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


_TOKEN_RE = re.compile(r"[^0-9a-z]+")


def normalize_search_text(value: str) -> str:
    text = unicodedata.normalize("NFKD", str(value)).encode("ascii", "ignore").decode("ascii").lower()
    return " ".join(part for part in _TOKEN_RE.split(text) if part)


@dataclass(frozen=True)
class SearchRecord:
    record_id: str
    kind: str
    display_text: str
    x: float
    y: float
    subtitle: str = ""
    search_text: str = ""

    def normalized_text(self) -> str:
        return self.search_text or normalize_search_text(f"{self.display_text} {self.subtitle}")


@dataclass(frozen=True)
class SearchResult:
    record_id: str
    kind: str
    display_text: str
    x: float
    y: float
    subtitle: str
    score: tuple[int, int, int, str]


class SearchIndex:
    """Deterministic in-memory search over compact normalized records."""

    def __init__(self, records: Iterable[SearchRecord]) -> None:
        self.records = tuple(sorted(records, key=lambda item: item.record_id))
        self._normalized = tuple(record.normalized_text() for record in self.records)

    def search(self, query: str, limit: int = 8) -> tuple[SearchResult, ...]:
        if limit <= 0:
            return ()
        normalized = normalize_search_text(query)
        if not normalized:
            return ()
        query_tokens = tuple(normalized.split())
        matches: list[SearchResult] = []
        for record, haystack in zip(self.records, self._normalized):
            score = _match_score(normalized, query_tokens, haystack, record.display_text, record.record_id)
            if score is None:
                continue
            matches.append(
                SearchResult(
                    record.record_id,
                    record.kind,
                    record.display_text,
                    record.x,
                    record.y,
                    record.subtitle,
                    score,
                )
            )
        matches.sort(key=lambda result: result.score)
        return tuple(matches[:limit])


def _match_score(
    query: str,
    query_tokens: tuple[str, ...],
    haystack: str,
    display_text: str,
    record_id: str,
) -> tuple[int, int, int, str] | None:
    """Rank visible-name matches first and use record identity as the final tie-break.

    Subtitle/disambiguation text remains searchable, but it must not reorder two
    records with the same visible name merely because one subtitle is shorter.
    """
    display = normalize_search_text(display_text)
    display_words = display.split()
    all_words = haystack.split()

    if query == display:
        tier = 0
    elif display.startswith(query):
        tier = 1
    elif query_tokens and all(any(word.startswith(token) for word in display_words) for token in query_tokens):
        tier = 2
    elif query in display:
        tier = 3
    elif query_tokens and all(any(word.startswith(token) for word in all_words) for token in query_tokens):
        tier = 4
    elif query in haystack:
        tier = 5
    else:
        return None

    return (tier, max(0, len(display) - len(query)), len(display_text), record_id)


def write_search_index(records: Iterable[SearchRecord], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    ordered = sorted(records, key=lambda item: item.record_id)
    with tmp.open("w", encoding="utf-8") as handle:
        handle.write(json.dumps({"format": "BSI1", "count": len(ordered)}, separators=(",", ":")) + "\n")
        for record in ordered:
            handle.write(
                json.dumps(
                    {
                        "id": record.record_id,
                        "kind": record.kind,
                        "display": record.display_text,
                        "subtitle": record.subtitle,
                        "x": record.x,
                        "y": record.y,
                        "search": record.normalized_text(),
                    },
                    ensure_ascii=False,
                    separators=(",", ":"),
                )
                + "\n"
            )
    tmp.replace(path)


def load_search_index(path: Path) -> SearchIndex:
    with path.open("r", encoding="utf-8") as handle:
        first = handle.readline()
        if not first:
            raise ValueError("BSI1 search index is empty")
        header = json.loads(first)
        if header.get("format") != "BSI1":
            raise ValueError("Unsupported search index format")
        records: list[SearchRecord] = []
        for line in handle:
            if not line.strip():
                continue
            item = json.loads(line)
            records.append(
                SearchRecord(
                    str(item["id"]),
                    str(item["kind"]),
                    str(item["display"]),
                    float(item["x"]),
                    float(item["y"]),
                    str(item.get("subtitle", "")),
                    str(item.get("search", "")),
                )
            )
    if int(header.get("count", -1)) != len(records):
        raise ValueError("BSI1 record count mismatch")
    return SearchIndex(records)
