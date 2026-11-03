-- =============================================================================
-- The four transfer-pricing formulas, in the order finance reads them.
--
--   (1) Sales centre      -> Plan centre    : (qty - returns) x sale price
--   (2) Production centre -> Plan centre    : receipt qty    x prod->plan price
--   (3) Plan centre       -> Production     : issue qty      x plan->prod price
--   (4) Stocktake gain - loss               : display only, not settled
--
-- Common filters: verifystate = 2 (approved), shop_id = -1 (not a store doc),
-- voucher_date inside one natural month. Department roll-up uses the code
-- prefix '40%' so every plant / workshop / line under the production centre
-- is included without a recursive query.
-- =============================================================================

-- (1) Sales centre -> Plan centre -------------------------------------------
SELECT d.code                                        AS department_code,
       d.name                                        AS department_name,
       mat.code                                      AS material_code,
       ROUND(SUM(l.qty - COALESCE(l.return_qty, 0)), 3)                    AS net_qty,
       ROUND(SUM((l.qty - COALESCE(l.return_qty, 0)) * p.sale_price), 2)   AS amount
FROM   sales_out_line l
JOIN   sales_out      h   ON h.id = l.header_id
LEFT   JOIN department d  ON d.id = h.department_id
JOIN   material       mat ON mat.id = l.material_id
JOIN   material_price p   ON p.id = mat.price_def_id      -- pointer lives on material
WHERE  h.verifystate = 2
  AND  h.shop_id = -1
  AND  h.voucher_date >= '2026-09-01' AND h.voucher_date < '2026-10-01'
GROUP  BY d.code, d.name, mat.code
ORDER  BY amount DESC;

-- (2) Production centre -> Plan centre --------------------------------------
SELECT d.code                                        AS department_code,
       d.name                                        AS department_name,
       mat.code                                      AS material_code,
       ROUND(SUM(l.qty), 3)                                                 AS receipt_qty,
       ROUND(SUM(l.qty * p.prod_to_plan), 2)                                AS amount
FROM   product_receipt_line l
JOIN   product_receipt h   ON h.id = l.header_id
LEFT   JOIN department d   ON d.id = h.department_id
JOIN   material        mat ON mat.id = l.material_id
JOIN   material_price  p   ON p.id = mat.price_def_id
WHERE  h.verifystate = 2
  AND  h.shop_id = -1
  AND  h.voucher_date >= '2026-09-01' AND h.voucher_date < '2026-10-01'
  AND  d.code LIKE '40%'                                  -- production centre subtree
GROUP  BY d.code, d.name, mat.code
ORDER  BY amount DESC;

-- (3) Plan centre -> Production (material issue only) -----------------------
SELECT d.code                                        AS department_code,
       d.name                                        AS department_name,
       mat.code                                      AS material_code,
       ROUND(SUM(l.qty), 3)                                                 AS issue_qty,
       ROUND(SUM(l.qty * p.plan_to_prod), 2)                                AS amount
FROM   material_issue_line l
JOIN   material_issue  h   ON h.id = l.header_id
LEFT   JOIN department d   ON d.id = h.department_id
JOIN   material        mat ON mat.id = l.material_id
JOIN   material_price  p   ON p.id = mat.price_def_id
WHERE  h.verifystate = 2
  AND  h.voucher_date >= '2026-09-01' AND h.voucher_date < '2026-10-01'
  AND  d.code LIKE '40%'
  AND  COALESCE(h.is_transfer, 0) = 0                     -- exclude warehouse transfers
GROUP  BY d.code, d.name, mat.code
ORDER  BY amount DESC;

-- (4) Stocktake gain minus loss (display column) ----------------------------
SELECT 'gain' AS side, mat.code AS material_code,
       ROUND(SUM(l.qty), 3) AS qty,
       ROUND(SUM(l.qty * p.prod_to_plan), 2) AS amount
FROM   other_in_line l
JOIN   other_in       h   ON h.id = l.header_id
JOIN   material       mat ON mat.id = l.material_id
JOIN   material_price p   ON p.id = mat.price_def_id
WHERE  h.verifystate = 2 AND h.shop_id = -1
  AND  h.bustype = '2481549820802632644'                 -- stocktake gain
  AND  h.voucher_date >= '2026-09-01' AND h.voucher_date < '2026-10-01'
GROUP  BY mat.code
UNION ALL
SELECT 'loss', mat.code,
       ROUND(SUM(l.qty), 3),
       ROUND(SUM(l.qty * p.prod_to_plan), 2)
FROM   other_out_line l
JOIN   other_out      h   ON h.id = l.header_id
JOIN   material       mat ON mat.id = l.material_id
JOIN   material_price p   ON p.id = mat.price_def_id
WHERE  h.verifystate = 2 AND h.shop_id = -1
  AND  h.bustype = '2481549820802632651'                 -- stocktake loss
  AND  h.voucher_date >= '2026-09-01' AND h.voucher_date < '2026-10-01'
GROUP  BY mat.code
ORDER  BY side DESC, amount DESC;
