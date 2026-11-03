-- =============================================================================
-- Validation: how an empty result set was traced to a single wrong JOIN.
--
-- "The query returns nothing" is the most common state in data work. Instead of
-- editing the SQL and re-running it blindly, count how many rows survive each
-- filter independently. Whichever layer collapses to zero is the culprit.
-- =============================================================================

-- (V1) Layer-by-layer survival count on the sales side.
--      In the client system this returned: 6453 / 6453 / 6453 / 6453 / 0 / 0
--      i.e. every business filter passed and only the price join died.
SELECT COUNT(*)                                                          AS all_rows,
       SUM(CASE WHEN h.verifystate = 2 THEN 1 ELSE 0 END)                AS approved_rows,
       SUM(CASE WHEN h.shop_id = -1 THEN 1 ELSE 0 END)                   AS non_store_rows,
       SUM(CASE WHEN h.department_id IS NOT NULL THEN 1 ELSE 0 END)      AS with_department,
       SUM(CASE WHEN mat.price_def_id IS NOT NULL THEN 1 ELSE 0 END)     AS material_with_pointer,
       SUM(CASE WHEN p.id IS NOT NULL THEN 1 ELSE 0 END)                 AS matched_price_row,
       SUM(CASE WHEN p.sale_price IS NOT NULL AND p.sale_price <> 0
                THEN 1 ELSE 0 END)                                       AS price_has_value
FROM   sales_out_line l
JOIN   sales_out      h   ON h.id = l.header_id
LEFT   JOIN material       mat ON mat.id = l.material_id
LEFT   JOIN material_price p   ON p.id = mat.price_def_id
WHERE  h.voucher_date >= '2026-09-01' AND h.voucher_date < '2026-10-01';

-- (V2) Cross-check: quantity x unit price must equal the stored amount.
--      Any row here is either a unit-of-measure mismatch or a data-entry error.
SELECT h.code AS issue_code, l.line_no,
       l.qty, l.unit_price, l.amount,
       ROUND(l.qty * l.unit_price, 2) AS computed
FROM   material_issue_line l
JOIN   material_issue      h ON h.id = l.header_id
WHERE  ABS(l.qty * l.unit_price - l.amount) > 0.01
ORDER  BY h.code, l.line_no;

-- (V3) Department distribution: which level of the org tree do documents
--      actually point at? (line / workshop / plant / centre)
SELECT d.code, d.name, COUNT(*) AS documents, ROUND(SUM(l.qty), 3) AS qty
FROM   product_receipt_line l
JOIN   product_receipt h ON h.id = l.header_id
LEFT   JOIN department d ON d.id = h.department_id
WHERE  h.verifystate = 2
  AND  h.voucher_date >= '2026-09-01' AND h.voucher_date < '2026-10-01'
GROUP  BY d.code, d.name
ORDER  BY qty DESC;

-- (V4) Transfer documents that must be excluded from formula (3).
SELECT h.code, h.voucher_date, h.is_transfer, ROUND(SUM(l.qty), 3) AS qty
FROM   material_issue_line l
JOIN   material_issue      h ON h.id = l.header_id
WHERE  COALESCE(h.is_transfer, 0) <> 0
  AND  h.voucher_date >= '2026-09-01' AND h.voucher_date < '2026-10-01'
GROUP  BY h.code, h.voucher_date, h.is_transfer;
