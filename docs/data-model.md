# Data model notes — where the documentation and the database disagree

Every row below is something a probe query proved. Nothing here is taken from vendor
documentation, because in four cases the documentation was wrong.

## 1. Join keys

| Layer | What the API / docs suggest | What the database actually has | How it was proven |
|---|---|---|---|
| Production receipt: header ↔ line | `mainid` | **`iMainId`** (and the join must also match the tenant column) | `SELECT * FROM <line> LIMIT 1` — column list |
| Sales issue: header ↔ line | `iMainId` (consistent with inventory) | **`imainid`** — all lowercase, same product, different module | column list of `st_salesouts` |
| Material → price extension | price row points at the material (`object_id = material.id`) | **pointer is on the material**: `material.product_character_def = price.id` | the price row's `object_id` was empty; the material JSON carried `productCharacterDef__id` equal to the price row's primary key |
| Org master | `iuap_apdoc_coredoc.org_orgs` (same schema as products) | **`iuap_apdoc_basedoc.org_orgs`** — master data and base documents are different schemas | the platform's own generated SQL referenced it 30 times |

**Lesson.** A join that returns zero rows looks identical to "no data exists". Always
prove a join key with a single-row probe before building an aggregate on top of it.

## 2. Column names that only exist in the API layer

| API field | Physical column | Notes |
|---|---|---|
| `productn` | `iProductid` | the `n` suffix is an API naming convention |
| `department_name` | not stored — join `org_orgs` | vouchers store the department **id** only |
| `cost_money` | **does not exist** on production receipts | exists on material issues; do not assume symmetry |
| `bustype_extend_attrs_json` | **does not exist** | the JSON attribute bag is assembled at the API layer; filtering on it fails |
| `subQty` | `subQty` (exists) | but often equals `qty`; see §3 |

## 3. Quantity columns: two candidates, one real

Material issue lines expose both `qty` and `fqty` (legacy reserved column).

```
fqty = 0 for every real document
qty × unit_price = amount   (exact, to the cent)
```

Decision: use `qty`; keep `amount` as an independent cross-check. The same test should
be run in any new module before trusting a quantity column.

## 4. Status enumerations: trust the data, not the dictionary

| Source | Claim |
|---|---|
| Copied enumeration list | `0 = pending, 1 = approved, 2 = closed, 3 = in approval` |
| One month of production receipts | 1,698 documents, **all** with `verifystate = 2`, all carrying an auditor and an audit timestamp |

A food plant does not run a month with zero approved receipts. The enumeration had been
copied with the indices shifted by one; `verifystate = 2` means **approved**.

**Rule adopted:** when dictionary, sample payload and live data disagree, arbitrate with
business sense and then verify against a UI count.

## 5. Prices

Four transfer prices, stored as `ncol45`–`ncol48` on the extension table, mapped to
business price items by codes:

| Column | Price item | Business meaning | Used by formula |
|---|---|---|---|
| `ncol45` | `NQ00052` | planning centre → sales centre | 1 |
| `ncol46` | `NQ00053` | planning centre → production | 3 |
| `ncol47` | `NQ00054` | production → planning centre | 2 · 4 |
| `ncol48` | `NQ00055` | sales centre | 1 |

The mapping was confirmed from SQL that the platform generated itself — which is a
better source of truth than any document, because it is the code that actually runs.

**Caveat.** Static fields have no effective-date dimension. Editing a price today
changes every historical report. That is a design gap, not a query bug.

## 6. Identifiers that look like data but are keys

- `iShopID = -1` means "not a retail-store document". Almost all warehouse documents
  carry it; a report that omits the filter double-counts store transfers.
- Transaction types (`bustype`) are opaque IDs. Mapping had to be established by
  grouping documents by type and matching sample document prefixes and remarks:

| ID | Meaning | Evidence |
|---|---|---|
| `…2644` | stocktake gain (other inbound) | 18 documents whose remark contained "stocktake"; symmetric position in the enum series with the loss id |
| `…2651` | stocktake loss (other outbound) | single document, quantity × price reconciled to the stated amount |

Never hard-code a `bustype` from documentation. Group by it, look at the sample
documents, then decide.
