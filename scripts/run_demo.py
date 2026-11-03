#!/usr/bin/env python3
"""Build the demo database and run every query in sql/.

Usage:
    python scripts/run_demo.py            # rebuild demo.db and print results
    python scripts/run_demo.py --keep     # keep demo.db for ad-hoc queries

Requires only the standard library (sqlite3).
"""

from __future__ import annotations

import argparse
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SQL_DIR = ROOT / "sql"


def statement_batches(path: Path):
    """Yield (index, statement) for a .sql file, ignoring comment-only chunks."""
    raw = path.read_text(encoding="utf-8")
    # Strip line comments first so a ';' inside a comment cannot split a statement.
    lines = [ln.split("--", 1)[0] for ln in raw.splitlines()]
    body = "\n".join(lines)
    for chunk in body.split(";"):
        stmt = chunk.strip()
        if stmt:
            yield stmt


def print_rows(cursor: sqlite3.Cursor) -> None:
    rows = cursor.fetchall()
    if not rows:
        print("    (no rows)")
        return
    headers = [d[0] for d in cursor.description]
    widths = [max(len(str(h)), *(len(str(r[i])) for r in rows)) for i, h in enumerate(headers)]
    print("    " + " | ".join(str(h).ljust(w) for h, w in zip(headers, widths)))
    print("    " + "-+-".join("-" * w for w in widths))
    for row in rows:
        print("    " + " | ".join(str(v).ljust(w) for v, w in zip(row, widths)))


def run(db_path: Path, keep: bool) -> None:
    if db_path.exists():
        db_path.unlink()

    conn = sqlite3.connect(db_path)
    conn.executescript((SQL_DIR / "01_schema.sql").read_text(encoding="utf-8"))
    conn.executescript((SQL_DIR / "02_seed.sql").read_text(encoding="utf-8"))

    for name in ("03_queries.sql", "04_validation.sql"):
        path = SQL_DIR / name
        print(f"\n=== {name} " + "=" * (60 - len(name)))
        for idx, stmt in enumerate(statement_batches(path), start=1):
            print(f"\n  [{name} #{idx}]")
            try:
                cur = conn.execute(stmt)
                print_rows(cur)
            except sqlite3.Error as exc:  # keep going so one bad query is visible
                print(f"    ERROR: {exc}")

    conn.commit()
    if not keep:
        conn.close()
        db_path.unlink()
        print("\nDemo database discarded (use --keep to retain demo.db).")
    else:
        conn.close()
        print(f"\nDemo database kept at {db_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep", action="store_true", help="keep demo.db after running")
    args = parser.parse_args()
    run(ROOT / "demo.db", args.keep)
