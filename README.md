# ERP Transfer Pricing — turning four business formulas into auditable SQL

[![demo](https://github.com/liyanchao123/erp-transfer-pricing/actions/workflows/demo.yml/badge.svg)](https://github.com/liyanchao123/erp-transfer-pricing/actions/workflows/demo.yml)
[![python](https://img.shields.io/badge/python-3.9%20%7C%203.12-blue)](https://www.python.org/)
[![license](https://img.shields.io/badge/license-MIT-green)](LICENSE)

A worked example of computing **internal settlement prices** (transfer pricing between
production, planning and sales centres) directly from an ERP database — including the
part nobody writes about: how the queries were made to reconcile with finance, and how
three wrong assumptions in the data model were found and fixed.

> All names, IDs and figures in this repository are **synthetic**. The document flow,
> the field-level traps and the decision log come from a real ERP delivery project;
> the data does not.

```bash
python scripts/run_demo.py          # build the demo DB and print every result set
python scripts/run_demo.py --check  # assert the expected figures, exit 1 on mismatch
```

No dependencies beyond the Python standard library. The script builds an in-memory
SQLite database from `sql/01_schema.sql` + `sql/02_seed.sql`, runs every query in
`sql/03_queries.sql` and `sql/04_validation.sql`, and prints the result sets.

`--check` re-runs the same pipeline as ten assertions — the four formulas, the
no-silent-zero-row join, `qty × unit_price = amount`, and the transfer volume that
formula 3 must skip. CI runs it on every push, on Python 3.9 and 3.12.

---

## The problem

A food manufacturer runs three responsibility centres — production, planning, sales —
and settles internally between them every month. Finance had four formulas living in a
spreadsheet:

| # | Business rule | Direction |
|---|---|---|
| 1 | (sales qty − returns) × sale price | sales centre → planning centre |
| 2 | good-receipt qty × production→planning price | production centre → planning centre |
| 3 | material-issue qty × planning→production price | planning centre → production centre |
| 4 | (stocktake gain − loss) × production→planning price | display only, not settled |

The spreadsheet worked, but it was manual, unauditable, and could not answer "why is
this line different from last month". The task was to reproduce it in SQL against the
ERP's own tables, so that any figure could be traced back to a document.

## What made it non-trivial

Four things, all of which cost time:

1. **The price data sat in a custom extension table** (`product_character_def_1`,
   columns `ncol45`–`ncol48`) and the pointer to it lives **on the material record**,
   not on the price row. Getting the join backwards returns zero rows silently — an
   INNER JOIN against an empty foreign key is indistinguishable from "there is no data".
2. **API field names ≠ database column names.** `productn` in the API is `iProductid`
   in the table; `iMainId` in one module is `imainid` (all lowercase) in another;
   `cost_money` exists on material issues but not on production receipts.
3. **Enumeration dictionaries were wrong.** The status dictionary said `2 = closed`,
   but every approved document in the period carried `verifystate = 2`. The dictionary
   had been mis-copied; the data was right.
4. **Two business rules were genuinely ambiguous** and had to be decided by the client,
   not by me — see `docs/decisions.md`.

## Method

Instead of writing the four queries and hoping, each unknown was turned into a
one-query probe, and the probe result decided the design:

```
assumption → probe query → observed value → design decision → documented
```

The most reusable artefact is `sql/04_validation.sql`: a **layer-by-layer survival
count** that shows how many rows remain after each filter. In the real system it
returned `6453 / 6453 / 6453 / 6453 / 0 / 0` — every business filter passed, and only
the price join matched nothing. That single result located the defect in one run
instead of six blind edits.

## Results (synthetic data, September 2026)

| Formula | Output | Amount |
|---|---|---|
| 1 · sales → planning | 4,800 kg net (5,000 shipped − 200 returned) | **48,000.00** |
| 2 · production → planning | 3,900 kg received | **39,000.00** |
| 3 · planning → production | 1,200 kg peanut + 800 kg flour | **9,920.00** |
| 4 · stocktake | 9,700.176 kg loss, 24.5 kg gain (display only) | **97,001.76 / 227.90** |

Every amount above is cross-checked two ways: against the document's own line amount
(`qty × unit_price`), and against the month's total reported by the ERP UI. The figures
are pinned by `scripts/run_demo.py --check` (10/10 assertions) and run on every push.

## Repository layout

```
sql/01_schema.sql        tables, with the naming traps annotated in comments
sql/02_seed.sql          synthetic September documents (sales, receipts, issues, counts)
sql/03_queries.sql       the four formulas
sql/04_validation.sql    layer diagnosis, amount reconciliation, department distribution
scripts/run_demo.py      builds demo.db, prints result sets, and asserts the figures
.github/workflows/       CI: runs the demo and the assertions on Python 3.9 / 3.12
docs/data-model.md       field-level map: API name → physical column → what it actually means
docs/decisions.md        the rule decisions and who made them
```

## Design notes

- **Department roll-up by code prefix** (`code LIKE '40%'`) instead of a recursive
  query. The org tree is encoded in the code (`40` → `4001` → `400101` → `40010101`),
  so a prefix match reaches every plant, workshop and line in one predicate. Cheap,
  readable, and it survives re-orgs as long as the coding rule holds.
- **Returns are handled inside the sales line** (`qty − return_qty`) rather than as
  red-line documents, because the ERP tracks them per line. Consequence: a return
  booked in month N+1 is deducted from month N's shipment. Documented, not hidden.
- **Warehouse transfers are excluded** from formula 3 (`is_transfer = 0`); they move
  stock without consuming it, and including them inflates internal purchases by 8×
  in the seed data — a useful reminder of why the filter matters.
- **Stocktake differences are shown, never settled.** The client wanted visibility,
  not an accounting entry.

## Limitations

- The demo uses SQLite; the production queries ran on MySQL 8 (schema-qualified names,
  `IFNULL`, backticked identifiers). Dialect differences are limited to those three.
- Prices are static fields in this schema — there is **no effective-date dimension**.
  Changing a price today silently rewrites history. See `docs/decisions.md`, decision 4.
- Single natural month, single organisation, one currency.

## License

MIT — see `LICENSE`.
