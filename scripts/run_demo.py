#!/usr/bin/env python3
"""Build the demo database and run every query in sql/.

Usage:
    python scripts/run_demo.py            # rebuild demo.db and print results
    python scripts/run_demo.py --keep     # keep demo.db for ad-hoc queries
    python scripts/run_demo.py --check    # assert the expected figures, exit 1 on mismatch

Requires only the standard library (sqlite3).
"""

from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SQL_DIR = ROOT / "sql"

MONTH = "h.voucher_date >= '2026-09-01' AND h.voucher_date < '2026-10-01'"

# (label, sql returning a single number, expected value, tolerance)
CHECKS = [
    (
        "formula 1 - net sales qty (5000 shipped, 200 returned)",
        f"""
        SELECT ROUND(SUM(l.qty - COALESCE(l.return_qty, 0)), 3)
        FROM sales_out_line l
        JOIN sales_out h ON h.id = l.header_id
        JOIN material mat ON mat.id = l.material_id
        JOIN material_price p ON p.id = mat.price_def_id
        WHERE h.verifystate = 2 AND h.shop_id = -1 AND {MONTH}
        """,
        4800.0,
        0.01,
    ),
    (
        "formula 1 - amount (4800 x sale price 10)",
        f"""
        SELECT ROUND(SUM((l.qty - COALESCE(l.return_qty, 0)) * p.sale_price), 2)
        FROM sales_out_line l
        JOIN sales_out h ON h.id = l.header_id
        JOIN material mat ON mat.id = l.material_id
        JOIN material_price p ON p.id = mat.price_def_id
        WHERE h.verifystate = 2 AND h.shop_id = -1 AND {MONTH}
        """,
        48000.0,
        0.01,
    ),
    (
        "formula 2 - receipt qty inside the production-centre subtree",
        f"""
        SELECT ROUND(SUM(l.qty), 3)
        FROM product_receipt_line l
        JOIN product_receipt h ON h.id = l.header_id
        JOIN department d ON d.id = h.department_id
        JOIN material mat ON mat.id = l.material_id
        JOIN material_price p ON p.id = mat.price_def_id
        WHERE h.verifystate = 2 AND h.shop_id = -1 AND d.code LIKE '40%' AND {MONTH}
        """,
        3900.0,
        0.01,
    ),
    (
        "formula 2 - amount (3900 x prod->plan price 10)",
        f"""
        SELECT ROUND(SUM(l.qty * p.prod_to_plan), 2)
        FROM product_receipt_line l
        JOIN product_receipt h ON h.id = l.header_id
        JOIN department d ON d.id = h.department_id
        JOIN material mat ON mat.id = l.material_id
        JOIN material_price p ON p.id = mat.price_def_id
        WHERE h.verifystate = 2 AND h.shop_id = -1 AND d.code LIKE '40%' AND {MONTH}
        """,
        39000.0,
        0.01,
    ),
    (
        "formula 3 - amount excludes the 9000 kg warehouse transfer",
        f"""
        SELECT ROUND(SUM(l.qty * p.plan_to_prod), 2)
        FROM material_issue_line l
        JOIN material_issue h ON h.id = l.header_id
        JOIN department d ON d.id = h.department_id
        JOIN material mat ON mat.id = l.material_id
        JOIN material_price p ON p.id = mat.price_def_id
        WHERE h.verifystate = 2 AND d.code LIKE '40%'
          AND COALESCE(h.is_transfer, 0) = 0 AND {MONTH}
        """,
        9920.0,
        0.01,
    ),
    (
        "formula 4 - stocktake loss qty",
        f"""
        SELECT ROUND(SUM(l.qty), 3)
        FROM other_out_line l
        JOIN other_out h ON h.id = l.header_id
        JOIN material mat ON mat.id = l.material_id
        JOIN material_price p ON p.id = mat.price_def_id
        WHERE h.verifystate = 2 AND h.shop_id = -1
          AND h.bustype = '2481549820802632651' AND {MONTH}
        """,
        9700.176,
        0.001,
    ),
    (
        "formula 4 - stocktake gain amount",
        f"""
        SELECT ROUND(SUM(l.qty * p.prod_to_plan), 2)
        FROM other_in_line l
        JOIN other_in h ON h.id = l.header_id
        JOIN material mat ON mat.id = l.material_id
        JOIN material_price p ON p.id = mat.price_def_id
        WHERE h.verifystate = 2 AND h.shop_id = -1
          AND h.bustype = '2481549820802632644' AND {MONTH}
        """,
        227.9,
        0.01,
    ),
    (
        "validation - every row keeps its price row (no silent zero-row join)",
        f"""
        SELECT CASE WHEN COUNT(*) = 0 THEN 0
                    ELSE ABS(COUNT(*) - SUM(CASE WHEN p.id IS NOT NULL THEN 1 ELSE 0 END))
               END
        FROM sales_out_line l
        JOIN sales_out h ON h.id = l.header_id
        LEFT JOIN material mat ON mat.id = l.material_id
        LEFT JOIN material_price p ON p.id = mat.price_def_id
        WHERE {MONTH}
        """,
        0.0,
        0.0,
    ),
    (
        "validation - qty x unit price = stored amount (mismatching rows)",
        f"""
        SELECT COUNT(*)
        FROM material_issue_line l
        JOIN material_issue h ON h.id = l.header_id
        WHERE ABS(l.qty * l.unit_price - l.amount) > 0.01
        """,
        0.0,
        0.0,
    ),
    (
        "validation - warehouse transfer volume that formula 3 must skip",
        f"""
        SELECT ROUND(SUM(l.qty), 3)
        FROM material_issue_line l
        JOIN material_issue h ON h.id = l.header_id
        WHERE COALESCE(h.is_transfer, 0) <> 0 AND {MONTH}
        """,
        9000.0,
        0.01,
    ),
]


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


def build(db_path: Path) -> sqlite3.Connection:
    if db_path.exists():
        db_path.unlink()
    conn = sqlite3.connect(db_path)
    conn.executescript((SQL_DIR / "01_schema.sql").read_text(encoding="utf-8"))
    conn.executescript((SQL_DIR / "02_seed.sql").read_text(encoding="utf-8"))
    return conn


def show(conn: sqlite3.Connection) -> None:
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


def check(conn: sqlite3.Connection) -> int:
    """Assert the figures the project claims. Returns the number of failures."""
    print("=== assertions " + "=" * 46)
    failures = 0
    for label, sql, expected, tol in CHECKS:
        value = conn.execute(sql).fetchone()[0]
        actual = 0.0 if value is None else float(value)
        ok = abs(actual - expected) <= tol
        if not ok:
            failures += 1
        print(f"  [{'PASS' if ok else 'FAIL'}] {label}")
        if not ok:
            print(f"         expected {expected}, got {actual}")
    print(f"\n{len(CHECKS) - failures}/{len(CHECKS)} assertions passed.")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep", action="store_true", help="keep demo.db after running")
    parser.add_argument(
        "--check",
        action="store_true",
        help="assert the expected figures and exit non-zero on mismatch",
    )
    args = parser.parse_args()

    db_path = ROOT / "demo.db"
    conn = build(db_path)
    failures = 0
    try:
        if args.check:
            failures = check(conn)
        else:
            show(conn)
    finally:
        conn.close()
        if not args.keep and db_path.exists():
            db_path.unlink()

    if args.keep:
        print(f"\nDemo database kept at {db_path}")
    elif not args.check:
        print("\nDemo database discarded (use --keep to retain demo.db).")

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
