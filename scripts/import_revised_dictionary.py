#!/usr/bin/env python3
"""Build the bundled SQLite dictionary from the Ministry of Education workbook."""

from __future__ import annotations

import argparse
import sqlite3
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET


NS = {"x": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
REL_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"


def text_value(value: str | None) -> str:
    if not value:
        return ""
    # Excel stores some line endings as a literal escape sequence in this file.
    return value.replace("_x000D_", "").replace("\r\n", "\n").replace("\r", "\n").strip()


def column_letter(cell_ref: str) -> str:
    return "".join(ch for ch in cell_ref if ch.isalpha())


def shared_strings(archive: zipfile.ZipFile) -> list[str]:
    root = ET.fromstring(archive.read("xl/sharedStrings.xml"))
    return ["".join(t.text or "" for t in si.iterfind(".//x:t", NS)) for si in root.findall("x:si", NS)]


def worksheet_path(archive: zipfile.ZipFile) -> str:
    workbook = ET.fromstring(archive.read("xl/workbook.xml"))
    rels = ET.fromstring(archive.read("xl/_rels/workbook.xml.rels"))
    targets = {rel.attrib["Id"]: rel.attrib["Target"] for rel in rels}
    first_sheet = workbook.find("x:sheets/x:sheet", NS)
    if first_sheet is None:
        raise RuntimeError("The workbook does not contain a worksheet")
    target = targets[first_sheet.attrib[f"{{{REL_NS}}}id"]]
    return target if target.startswith("xl/") else f"xl/{target}"


def rows_from_workbook(source: Path):
    with zipfile.ZipFile(source) as archive:
        strings = shared_strings(archive)
        root = ET.fromstring(archive.read(worksheet_path(archive)))
        for row in root.findall(".//x:sheetData/x:row", NS):
            values: dict[str, str] = {}
            for cell in row.findall("x:c", NS):
                ref = cell.attrib.get("r", "")
                kind = cell.attrib.get("t")
                value_node = cell.find("x:v", NS)
                value = "" if value_node is None else value_node.text or ""
                if kind == "s":
                    value = strings[int(value)]
                elif kind == "inlineStr":
                    value = "".join(t.text or "" for t in cell.iterfind(".//x:t", NS))
                values[column_letter(ref)] = value
            yield values


def build_database(source: Path, output: Path) -> tuple[int, int]:
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.unlink()

    connection = sqlite3.connect(output)
    try:
        connection.execute("PRAGMA journal_mode = OFF")
        connection.execute("PRAGMA synchronous = OFF")
        connection.execute(
            """
            CREATE TABLE dict_mini (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                word TEXT NOT NULL,
                entry_alias TEXT NOT NULL DEFAULT '',
                word_length INTEGER NOT NULL DEFAULT 0,
                entry_id TEXT NOT NULL DEFAULT '',
                radical TEXT NOT NULL DEFAULT '',
                stroke_count INTEGER NOT NULL DEFAULT 0,
                outside_radical_strokes INTEGER NOT NULL DEFAULT 0,
                pronunciation_order INTEGER NOT NULL DEFAULT 0,
                phonetic TEXT NOT NULL DEFAULT '',
                variant_type TEXT NOT NULL DEFAULT '',
                variant_phonetic TEXT NOT NULL DEFAULT '',
                pinyin TEXT NOT NULL DEFAULT '',
                variant_pinyin TEXT NOT NULL DEFAULT '',
                synonyms TEXT NOT NULL DEFAULT '',
                antonyms TEXT NOT NULL DEFAULT '',
                definition TEXT NOT NULL DEFAULT '',
                pronunciation_note TEXT NOT NULL DEFAULT '',
                variant_characters TEXT NOT NULL DEFAULT ''
            );
            """
        )

        insert_sql = """
            INSERT INTO dict_mini (
                word, entry_alias, word_length, entry_id, radical, stroke_count,
                outside_radical_strokes, pronunciation_order, phonetic, variant_type,
                variant_phonetic, pinyin, variant_pinyin, synonyms, antonyms,
                definition, pronunciation_note, variant_characters
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        total = 0
        distinct_words: set[str] = set()
        iterator = rows_from_workbook(source)
        next(iterator)  # header row
        for row in iterator:
            word = text_value(row.get("A"))
            if not word:
                continue
            distinct_words.add(word)
            connection.execute(
                insert_sql,
                (
                    word,
                    text_value(row.get("B")),
                    int(text_value(row.get("C")) or 0),
                    text_value(row.get("D")),
                    text_value(row.get("E")),
                    int(text_value(row.get("F")) or 0),
                    int(text_value(row.get("G")) or 0),
                    int(text_value(row.get("H")) or 0),
                    text_value(row.get("I")),
                    text_value(row.get("J")),
                    text_value(row.get("K")),
                    text_value(row.get("L")),
                    text_value(row.get("M")),
                    text_value(row.get("N")),
                    text_value(row.get("O")),
                    text_value(row.get("P")),
                    text_value(row.get("Q")),
                    text_value(row.get("R")),
                ),
            )
            total += 1

        connection.execute("CREATE INDEX idx_dict_word ON dict_mini(word)")
        connection.execute("CREATE INDEX idx_dict_phonetic ON dict_mini(phonetic)")
        connection.execute("CREATE INDEX idx_dict_pinyin ON dict_mini(pinyin)")
        connection.execute("CREATE INDEX idx_dict_word_length ON dict_mini(word, word_length)")
        connection.execute("CREATE TABLE dictionary_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        connection.executemany(
            "INSERT INTO dictionary_metadata(key, value) VALUES (?, ?)",
            [
                ("source_id", "dict_revised_2015_20260929"),
                ("source_title", "教育部《重編國語辭典修訂本》"),
                ("source_license", "CC BY-ND 3.0 Taiwan"),
            ],
        )
        connection.execute("PRAGMA user_version = 2")
        connection.commit()
        return total, len(distinct_words)
    finally:
        connection.close()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    total, distinct = build_database(args.source, args.output)
    print(f"Imported {total:,} entries ({distinct:,} distinct words) into {args.output}")


if __name__ == "__main__":
    main()
