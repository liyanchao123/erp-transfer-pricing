-- =============================================================================
-- erp-transfer-pricing · demo schema (SQLite)
--
-- This schema mirrors the *shape* of a YonBIP / Yonyou BIP inventory stack,
-- including the three naming idiosyncrasies that cost me two days (see
-- docs/data-model.md). Names are simplified, not the vendor's physical names.
--
-- All figures in the seed data are synthetic. No client data is included.
-- =============================================================================

DROP TABLE IF EXISTS department;
DROP TABLE IF EXISTS material_price;
DROP TABLE IF EXISTS material;
DROP TABLE IF EXISTS sales_out;
DROP TABLE IF EXISTS sales_out_line;
DROP TABLE IF EXISTS product_receipt;
DROP TABLE IF EXISTS product_receipt_line;
DROP TABLE IF EXISTS material_issue;
DROP TABLE IF EXISTS material_issue_line;
DROP TABLE IF EXISTS other_in;
DROP TABLE IF EXISTS other_in_line;
DROP TABLE IF EXISTS other_out;
DROP TABLE IF EXISTS other_out_line;

-- Org tree. Real system: iuap_apdoc_basedoc.org_orgs (NOT coredoc — that is
-- the main-data schema; the org master lives in the base-document schema).
-- Hierarchy is rolled up with prefix matching on `code`, e.g. LEFT(code,2)='40'.
CREATE TABLE department (
    id          INTEGER PRIMARY KEY,
    code        TEXT    NOT NULL,          -- '40' = production centre, '4001' = plant 1 ...
    name        TEXT    NOT NULL,
    parent_id   INTEGER REFERENCES department(id)
);

-- Price extension. In the real schema this lives in a separate table
-- (product_character_def_1) addressed by a pointer column ON the material —
-- not the other way round. Getting this direction wrong silently returns
-- zero rows (INNER JOIN + empty key = empty result).
CREATE TABLE material_price (
    id              INTEGER PRIMARY KEY,
    plan_to_sale    REAL,   -- ncol45 / NQ00052  plan centre -> sales centre
    plan_to_prod    REAL,   -- ncol46 / NQ00053  plan centre -> production
    prod_to_plan    REAL,   -- ncol47 / NQ00054  production   -> plan centre
    sale_price      REAL    -- ncol48 / NQ00055  sales centre
);

CREATE TABLE material (
    id          INTEGER PRIMARY KEY,
    code        TEXT    NOT NULL UNIQUE,
    name        TEXT    NOT NULL,
    uom         TEXT    NOT NULL DEFAULT 'kg',
    price_def_id INTEGER REFERENCES material_price(id)   -- the pointer column
);

-- Sales issue (delivery note). Returns are tracked per line, not as red lines.
CREATE TABLE sales_out (
    id            INTEGER PRIMARY KEY,
    code          TEXT    NOT NULL,
    voucher_date  TEXT    NOT NULL,
    department_id INTEGER REFERENCES department(id),
    verifystate   INTEGER NOT NULL DEFAULT 2,   -- 2 = approved (empirically; dictionary lies)
    shop_id       INTEGER NOT NULL DEFAULT -1   -- -1 = not a retail-store document
);

CREATE TABLE sales_out_line (
    header_id   INTEGER NOT NULL REFERENCES sales_out(id),
    line_no     INTEGER NOT NULL,
    material_id INTEGER NOT NULL REFERENCES material(id),
    qty         REAL    NOT NULL,
    return_qty  REAL    DEFAULT 0,
    PRIMARY KEY (header_id, line_no)
);

-- Production receipt (finished goods received from the shop floor).
CREATE TABLE product_receipt (
    id            INTEGER PRIMARY KEY,
    code          TEXT    NOT NULL,
    voucher_date  TEXT    NOT NULL,
    department_id INTEGER REFERENCES department(id),
    verifystate   INTEGER NOT NULL DEFAULT 2,
    shop_id       INTEGER NOT NULL DEFAULT -1
);

CREATE TABLE product_receipt_line (
    header_id   INTEGER NOT NULL REFERENCES product_receipt(id),
    line_no     INTEGER NOT NULL,
    material_id INTEGER NOT NULL REFERENCES material(id),
    qty         REAL    NOT NULL,
    unit_cost   REAL,
    PRIMARY KEY (header_id, line_no)
);

-- Material issue (raw material consumed by production).
-- NOTE: the *line* table has both `qty` and a legacy `fqty` column in the real
-- system; `fqty` was always 0 and `qty` reconciled against amount/unit price.
CREATE TABLE material_issue (
    id            INTEGER PRIMARY KEY,
    code          TEXT    NOT NULL,
    voucher_date  TEXT    NOT NULL,
    department_id INTEGER REFERENCES department(id),
    verifystate   INTEGER NOT NULL DEFAULT 2,
    is_transfer   INTEGER DEFAULT 0            -- 1 = warehouse transfer, exclude
);

CREATE TABLE material_issue_line (
    header_id   INTEGER NOT NULL REFERENCES material_issue(id),
    line_no     INTEGER NOT NULL,
    material_id INTEGER NOT NULL REFERENCES material(id),
    qty         REAL    NOT NULL,
    unit_price  REAL,
    amount      REAL,
    PRIMARY KEY (header_id, line_no)
);

-- Other inbound / outbound documents carry stocktake differences.
-- bustype is an opaque ID; the mapping had to be established empirically:
--   other_in  2481549820802632644 = stocktake gain
--   other_out 2481549820802632651 = stocktake loss
CREATE TABLE other_in (
    id            INTEGER PRIMARY KEY,
    code          TEXT    NOT NULL,
    voucher_date  TEXT    NOT NULL,
    department_id INTEGER REFERENCES department(id),
    bustype       TEXT    NOT NULL,
    verifystate   INTEGER NOT NULL DEFAULT 2,
    shop_id       INTEGER NOT NULL DEFAULT -1
);

CREATE TABLE other_in_line (
    header_id   INTEGER NOT NULL REFERENCES other_in(id),
    line_no     INTEGER NOT NULL,
    material_id INTEGER NOT NULL REFERENCES material(id),
    qty         REAL    NOT NULL,
    PRIMARY KEY (header_id, line_no)
);

CREATE TABLE other_out (
    id            INTEGER PRIMARY KEY,
    code          TEXT    NOT NULL,
    voucher_date  TEXT    NOT NULL,
    department_id INTEGER REFERENCES department(id),
    bustype       TEXT    NOT NULL,
    verifystate   INTEGER NOT NULL DEFAULT 2,
    shop_id       INTEGER NOT NULL DEFAULT -1
);

CREATE TABLE other_out_line (
    header_id   INTEGER NOT NULL REFERENCES other_out(id),
    line_no     INTEGER NOT NULL,
    material_id INTEGER NOT NULL REFERENCES material(id),
    qty         REAL    NOT NULL,
    PRIMARY KEY (header_id, line_no)
);
