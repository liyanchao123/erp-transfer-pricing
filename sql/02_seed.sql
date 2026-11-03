-- =============================================================================
-- Synthetic seed data · September 2026
-- Structure follows the client's real document flow; every value is fabricated.
-- =============================================================================

-- --- Org tree: production centre with three plants and two lines -------------
INSERT INTO department (id, code, name, parent_id) VALUES
    (1, '40',    'Production Centre',        NULL),
    (2, '4001',  'Plant 1 (Peanut)',         1),
    (3, '4002',  'Plant 2 (Printing)',       1),
    (4, '4003',  'Plant 3 (North Workshop)', 1),
    (11,'400101','Plant 1 / Workshop A',     2),
    (12,'40010101','Line A1 (8g sachet)',    11),
    (13,'40010102','Line A2 (15g sachet)',   11);

-- --- Price extension: four transfer prices per material ---------------------
-- All four prices are deliberately different so a reversed mapping is visible.
INSERT INTO material_price (id, plan_to_sale, plan_to_prod, prod_to_plan, sale_price) VALUES
    (9001, 10.00, 10.00, 10.00, 10.00),   -- finished good, all four = 10.00 (as recorded by the client)
    (9002,  6.50,  6.20,  6.20,  7.00),   -- raw peanut
    (9003,  3.20,  3.10,  3.00,  3.50);   -- wheat flour

INSERT INTO material (id, code, name, uom, price_def_id) VALUES
    (101, 'FG-PEANUT-8G', 'Peanut sachet 8g (finished)', 'kg',  9001),
    (201, 'RM-PEANUT',    'Peanut kernel (raw)',         'kg',  9002),
    (202, 'RM-FLOUR',     'Wheat flour',                 'kg',  9003);

-- --- Sales issue (finished goods) -------------------------------------------
INSERT INTO sales_out (id, code, voucher_date, department_id, verifystate, shop_id) VALUES
    (5001, 'XSCKD2609010001', '2026-09-03', 12, 2, -1),
    (5002, 'XSCKD2609150012', '2026-09-15', 12, 2, -1),
    (5003, 'XSCKD2609280027', '2026-09-28', 12, 2, -1);

INSERT INTO sales_out_line (header_id, line_no, material_id, qty, return_qty) VALUES
    (5001, 1, 101, 2000, 0),
    (5002, 1, 101, 2500, 200),
    (5003, 1, 101,  500, 0);

-- --- Production receipt (finished goods received from line A1) --------------
INSERT INTO product_receipt (id, code, voucher_date, department_id, verifystate, shop_id) VALUES
    (6001, 'CPRKD2609020042', '2026-09-02', 12, 2, -1),
    (6002, 'CPRKD2609180110', '2026-09-18', 12, 2, -1);

INSERT INTO product_receipt_line (header_id, line_no, material_id, qty, unit_cost) VALUES
    (6001, 1, 101, 2000, 9.80),
    (6002, 1, 101, 1900, 9.95);

-- --- Material issue (raw material consumed by the line) ---------------------
-- One document is a pure warehouse transfer and must be excluded.
INSERT INTO material_issue (id, code, voucher_date, department_id, verifystate, is_transfer) VALUES
    (7001, 'CLCKD2609020015', '2026-09-02', 12, 2, 0),
    (7002, 'CLCKD2609180111', '2026-09-18', 12, 2, 0),
    (7003, 'CLCKD2609250300', '2026-09-25', 12, 2, 1);   -- transfer: excluded

INSERT INTO material_issue_line (header_id, line_no, material_id, qty, unit_price, amount) VALUES
    (7001, 1, 201,  700, 6.20,  4340.00),
    (7001, 2, 202,  500, 3.10,  1550.00),
    (7002, 1, 201,  500, 6.20,  3100.00),
    (7002, 2, 202,  300, 3.10,   930.00),
    (7003, 1, 201, 9000, 6.20, 55800.00);   -- must not appear in the result

-- --- Stocktake differences (display column only, not settled) ---------------
INSERT INTO other_in (id, code, voucher_date, department_id, bustype, verifystate, shop_id) VALUES
    (8001, 'QTRKD2609300007', '2026-09-30', 1, '2481549820802632644', 2, -1);

INSERT INTO other_in_line (header_id, line_no, material_id, qty) VALUES
    (8001, 1, 101, 20),
    (8001, 2, 201, 4.5);

INSERT INTO other_out (id, code, voucher_date, department_id, bustype, verifystate, shop_id) VALUES
    (8101, 'QTCKD2609300035', '2026-09-30', 1, '2481549820802632651', 2, -1);

INSERT INTO other_out_line (header_id, line_no, material_id, qty) VALUES
    (8101, 1, 101, 9700.1763);
