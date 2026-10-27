#!/usr/bin/env python3
"""Verify that every source column is represented in the bundled SQLite file."""

from __future__ import annotations

import re
import sqlite3
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from import_revised_dictionary import rows_from_workbook, text_value  # noqa: E402


SOURCE_COLUMNS = list("ABCDEFGHIJKLMNOPQR")
DB_COLUMNS = [
    "word", "entry_alias", "word_length", "entry_id", "radical", "stroke_count",
    "outside_radical_strokes", "pronunciation_order", "phonetic", "variant_type",
    "variant_phonetic", "pinyin", "variant_pinyin", "synonyms", "antonyms",
    "definition", "pronunciation_note", "variant_characters",
]


def main() -> int:
    source = Path("dict_revised_2015_20260929/dict_revised_2015_20260929.xlsx")
    database = Path("StudentDict/dictionary.sqlite")
    source_counts = Counter()
    source_max_lengths = Counter()
    source_rows = 0

    for index, row in enumerate(rows_from_workbook(source)):
        if index == 0:
            continue
        word = text_value(row.get("A"))
        if not word:
            continue
        source_rows += 1
        for source_column in SOURCE_COLUMNS:
            value = text_value(row.get(source_column))
            if value:
                source_counts[source_column] += 1
            source_max_lengths[source_column] = max(source_max_lengths[source_column], len(value))

    connection = sqlite3.connect(database)
    try:
        db_rows = connection.execute("SELECT COUNT(*) FROM dict_mini").fetchone()[0]
        if db_rows != source_rows:
            raise AssertionError(f"row count mismatch: source={source_rows}, database={db_rows}")

        for source_column, db_column in zip(SOURCE_COLUMNS, DB_COLUMNS):
            if db_column in {"word_length", "stroke_count", "outside_radical_strokes", "pronunciation_order"}:
                db_count = connection.execute(
                    f"SELECT COUNT(*) FROM dict_mini WHERE {db_column} != 0"
                ).fetchone()[0]
            else:
                db_count = connection.execute(
                    f"SELECT COUNT(*) FROM dict_mini WHERE {db_column} != ''"
                ).fetchone()[0]
            db_max_length = connection.execute(
                f"SELECT MAX(LENGTH({db_column})) FROM dict_mini"
            ).fetchone()[0] or 0
            # Numeric zero is the source's explicit default for these fields.
            if db_column not in {"word_length", "stroke_count", "outside_radical_strokes", "pronunciation_order"}:
                if db_count != source_counts[source_column]:
                    raise AssertionError(
                        f"non-empty mismatch {source_column}/{db_column}: "
                        f"source={source_counts[source_column]}, database={db_count}"
                    )
            if db_max_length != source_max_lengths[source_column]:
                raise AssertionError(
                    f"max length mismatch {source_column}/{db_column}: "
                    f"source={source_max_lengths[source_column]}, database={db_max_length}"
                )

        token_pattern = re.compile(r"&([^;\n]{1,80});")
        tokens = set()
        for word, definition in connection.execute("SELECT word, definition FROM dict_mini"):
            tokens.update(token_pattern.findall(f"{word}\n{definition}"))
        missing = [token for token in sorted(tokens) if not (Path("StudentDict/MOEImages") / token).exists()]
        if missing:
            raise AssertionError(f"missing MOE image assets: {missing}")

        integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
        if integrity != "ok":
            raise AssertionError(f"SQLite integrity check failed: {integrity}")
    finally:
        connection.close()

    print(f"OK: {source_rows:,} rows; all 18 source columns verified; {len(tokens):,} image tokens resolved")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
