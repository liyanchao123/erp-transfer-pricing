# Decision log

Five rules had to be settled before the numbers could be trusted. Four of them were
**not** technical decisions — they were business decisions that a developer must hand
back to the client. Writing them down is the difference between "a query" and "a
settlement rule".

---

## 1. Does "material issue" include production consumption booked through other outbound documents?

**Context.** Material issues (`st_materialout`) are the official channel for raw
material consumption. But a sample of 40+ "other outbound" documents showed remarks
such as *"used for peanut marinating"*, *"used for production mixing"*, and regular
issues from the R&D department. That is production consumption booked outside the
material-issue module.

**Options.**
- A. Material-issue documents only → narrower, matches the literal wording of the rule.
- B. Material issues + production-type other outbound → wider, closer to physical reality.

**Decision:** **A** — client's call, after being shown the difference between the two
totals. Recorded in the settlement rules, not just in the SQL.

**Consequence.** Formula 3 under-reports consumption to the extent that production
uses other outbound documents. The exposure is documented and quantifiable on demand
(run both variants, show the delta). This is a governance problem to fix in process,
not a bug to fix in SQL.

---

## 2. How are returns handled — inside the line, or as red-line documents?

**Context.** Sales lines carry a `return_qty` field. Returns could also be booked as
negative-quantity documents.

**Evidence.** One month of sales: a single stock direction value, no negative lines,
and `return_qty ≤ qty` on every row, including three full reversals
(`450 = 450`, `510 = 510`, `26.25 = 26.25`).

**Decision:** **inside the line** — `SUM(qty − return_qty)`.

**Consequence.** A return booked in month N+1 is deducted from month N, because it is
attached to the original shipment line. For this client the return cycle is a few days,
so the distortion is negligible — but it is stated in the settlement rules and in the
README limitations. If the return cycle were long, the correct design would be a
separate query on return documents by return date.

---

## 3. Do stocktake differences enter the settlement, or are they display-only?

**Context.** Formula 4 exists in the spreadsheet, and the client's answer was:
"show it, don't settle it" — plus "documents without a department belong to the
production centre".

**Decision:** compute and display; exclude from the three settlement amounts; fall back
to the production centre when the department is empty.

**Consequence.** The displayed figure is not zero-sum against the other three formulas.
This is intentional and must be explained in the report footer, otherwise finance will
try to reconcile it.

---

## 4. What happens when a price is edited after the month is closed?

**Context.** Prices are static custom fields. There is no effective date.

**Decision:** accept the limitation for the pilot; flag it as a design gap and propose
a price-scheme (`material + org + effective period`) as the long-term fix.

**Consequence.** Historical reports are not reproducible once a price changes. Mitigation
for now: export the four prices to a signed snapshot at every month-end close. This is
the single most important non-technical risk in the whole solution, because it is
invisible until someone asks "why did last quarter's report change?".

---

## 5. Which department level is the reporting dimension?

**Context.** The org tree has four levels: centre → plant → workshop → line. Documents
point at the line (`40010101`), while management reports at plant level.

**Decision:** store at the level the document carries (line), roll up by code prefix
(`LEFT(code, 2) = '40'` for the centre; `LEFT(code, 4)` for a plant).

**Consequence.** No recursive query, no `parent_id` traversal. It depends on the coding
convention being maintained — verify it once per period with
`sql/04_validation.sql` (V3), which shows the distribution of departments actually used.
