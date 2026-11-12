-- 2. Двойной NOT EXISTS

WITH target_states(state) AS (
    VALUES ('AL'), ('SE'), ('BA')
), cat_state AS (
    SELECT DISTINCT p.product_category_name AS category, c.customer_state AS state
    FROM olist.order_items oi
    JOIN olist.orders o    ON o.order_id = oi.order_id
    JOIN olist.customers c ON c.customer_id = o.customer_id
    JOIN olist.products p  ON p.product_id = oi.product_id
    WHERE o.order_status = 'delivered'
      AND p.product_category_name IS NOT NULL AND p.product_category_name <> ''
), cats AS (
    SELECT DISTINCT category FROM cat_state
)
SELECT cats.category
FROM cats
WHERE NOT EXISTS (
    SELECT 1 FROM target_states t
    WHERE NOT EXISTS (
        SELECT 1 FROM cat_state cs
        WHERE cs.category = cats.category AND cs.state = t.state))
ORDER BY cats.category;

-- 3. GROUP BY / HAVING COUNT(DISTINCT)
WITH target_states(state) AS (
    VALUES ('AL'), ('SE'), ('BA')
), cat_state AS (
    SELECT DISTINCT p.product_category_name AS category, c.customer_state AS state
    FROM olist.order_items oi
    JOIN olist.orders o    ON o.order_id = oi.order_id
    JOIN olist.customers c ON c.customer_id = o.customer_id
    JOIN olist.products p  ON p.product_id = oi.product_id
    WHERE o.order_status = 'delivered'
      AND p.product_category_name IS NOT NULL AND p.product_category_name <> ''
)
SELECT cs.category
FROM cat_state cs
JOIN target_states t ON t.state = cs.state
GROUP BY cs.category
HAVING count(DISTINCT cs.state) = (SELECT count(*) FROM target_states)
ORDER BY cs.category;

-- 4. EXCEPT + NOT EXISTS
WITH target_states(state) AS (
    VALUES ('AL'), ('SE'), ('BA')
), cat_state AS (
    SELECT DISTINCT p.product_category_name AS category, c.customer_state AS state
    FROM olist.order_items oi
    JOIN olist.orders o    ON o.order_id = oi.order_id
    JOIN olist.customers c ON c.customer_id = o.customer_id
    JOIN olist.products p  ON p.product_id = oi.product_id
    WHERE o.order_status = 'delivered'
      AND p.product_category_name IS NOT NULL AND p.product_category_name <> ''
), cats AS (
    SELECT DISTINCT category FROM cat_state
)
SELECT cats.category
FROM cats
WHERE NOT EXISTS (
    SELECT state FROM target_states
    EXCEPT
    SELECT cs.state FROM cat_state cs WHERE cs.category = cats.category)
ORDER BY cats.category;

-- 5. Эквивалентность трёх реализаций
WITH target_states(state) AS (
    VALUES ('AL'), ('SE'), ('BA')
), cat_state AS (
    SELECT DISTINCT p.product_category_name AS category, c.customer_state AS state
    FROM olist.order_items oi
    JOIN olist.orders o    ON o.order_id = oi.order_id
    JOIN olist.customers c ON c.customer_id = o.customer_id
    JOIN olist.products p  ON p.product_id = oi.product_id
    WHERE o.order_status = 'delivered'
      AND p.product_category_name IS NOT NULL AND p.product_category_name <> ''
), cats AS (
    SELECT DISTINCT category FROM cat_state
), r1 AS (
    SELECT cats.category FROM cats
    WHERE NOT EXISTS (
        SELECT 1 FROM target_states t
        WHERE NOT EXISTS (
            SELECT 1 FROM cat_state cs
            WHERE cs.category = cats.category AND cs.state = t.state))
), r2 AS (
    SELECT cs.category
    FROM cat_state cs
    JOIN target_states t ON t.state = cs.state
    GROUP BY cs.category
    HAVING count(DISTINCT cs.state) = (SELECT count(*) FROM target_states)
), r3 AS (
    SELECT cats.category FROM cats
    WHERE NOT EXISTS (
        SELECT state FROM target_states
        EXCEPT
        SELECT cs.state FROM cat_state cs WHERE cs.category = cats.category)
)
SELECT 'cnt r1 / r2 / r3' AS check_name,
       (SELECT count(*) FROM r1) AS v1, (SELECT count(*) FROM r2) AS v2, (SELECT count(*) FROM r3) AS v3
UNION ALL
SELECT 'r1 - r2 / r2 - r1 / r1 - r3',
       (SELECT count(*) FROM (SELECT * FROM r1 EXCEPT SELECT * FROM r2) a),
       (SELECT count(*) FROM (SELECT * FROM r2 EXCEPT SELECT * FROM r1) b),
       (SELECT count(*) FROM (SELECT * FROM r1 EXCEPT SELECT * FROM r3) c)
UNION ALL
SELECT 'r3 - r1 / r2 - r3 / r3 - r2',
       (SELECT count(*) FROM (SELECT * FROM r3 EXCEPT SELECT * FROM r1) d),
       (SELECT count(*) FROM (SELECT * FROM r2 EXCEPT SELECT * FROM r3) e),
       (SELECT count(*) FROM (SELECT * FROM r3 EXCEPT SELECT * FROM r2) f);

-- 6. Диагностика для одной категории
WITH target_states(state) AS (
    VALUES ('AL'), ('SE'), ('BA')
), cat_state AS (
    SELECT DISTINCT p.product_category_name AS category, c.customer_state AS state
    FROM olist.order_items oi
    JOIN olist.orders o    ON o.order_id = oi.order_id
    JOIN olist.customers c ON c.customer_id = o.customer_id
    JOIN olist.products p  ON p.product_id = oi.product_id
    WHERE o.order_status = 'delivered'
      AND p.product_category_name IS NOT NULL AND p.product_category_name <> ''
), found AS (
    SELECT cs.category
    FROM cat_state cs
    JOIN target_states t ON t.state = cs.state
    GROUP BY cs.category
    HAVING count(DISTINCT cs.state) = (SELECT count(*) FROM target_states)
    ORDER BY cs.category
    LIMIT 1
)
SELECT f.category,
       c.customer_state AS state,
       count(DISTINCT o.order_id) AS orders_cnt
FROM found f
JOIN olist.products p  ON p.product_category_name = f.category
JOIN olist.order_items oi ON oi.product_id = p.product_id
JOIN olist.orders o    ON o.order_id = oi.order_id
JOIN olist.customers c ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered'
  AND c.customer_state IN (SELECT state FROM target_states)
GROUP BY f.category, c.customer_state
ORDER BY c.customer_state;

-- 7. Пустой target_states
WITH target_states(state) AS (
    SELECT state FROM (VALUES ('AL'), ('SE'), ('BA')) v(state) WHERE false
), cat_state AS (
    SELECT DISTINCT p.product_category_name AS category, c.customer_state AS state
    FROM olist.order_items oi
    JOIN olist.orders o    ON o.order_id = oi.order_id
    JOIN olist.customers c ON c.customer_id = o.customer_id
    JOIN olist.products p  ON p.product_id = oi.product_id
    WHERE o.order_status = 'delivered'
      AND p.product_category_name IS NOT NULL AND p.product_category_name <> ''
), cats AS (
    SELECT DISTINCT category FROM cat_state
)
SELECT count(*) AS empty_not_exists_cnt
FROM cats
WHERE NOT EXISTS (
    SELECT 1 FROM target_states t
    WHERE NOT EXISTS (
        SELECT 1 FROM cat_state cs
        WHERE cs.category = cats.category AND cs.state = t.state));

-- EXCEPT + NOT EXISTS
WITH target_states(state) AS (
    SELECT state FROM (VALUES ('AL'), ('SE'), ('BA')) v(state) WHERE false
), cat_state AS (
    SELECT DISTINCT p.product_category_name AS category, c.customer_state AS state
    FROM olist.order_items oi
    JOIN olist.orders o    ON o.order_id = oi.order_id
    JOIN olist.customers c ON c.customer_id = o.customer_id
    JOIN olist.products p  ON p.product_id = oi.product_id
    WHERE o.order_status = 'delivered'
      AND p.product_category_name IS NOT NULL AND p.product_category_name <> ''
), cats AS (
    SELECT DISTINCT category FROM cat_state
)
SELECT count(*) AS empty_except_cnt
FROM cats
WHERE NOT EXISTS (
    SELECT state FROM target_states
    EXCEPT
    SELECT cs.state FROM cat_state cs WHERE cs.category = cats.category);

-- HAVING COUNT
WITH target_states(state) AS (
    SELECT state FROM (VALUES ('AL'), ('SE'), ('BA')) v(state) WHERE false
), cat_state AS (
    SELECT DISTINCT p.product_category_name AS category, c.customer_state AS state
    FROM olist.order_items oi
    JOIN olist.orders o    ON o.order_id = oi.order_id
    JOIN olist.customers c ON c.customer_id = o.customer_id
    JOIN olist.products p  ON p.product_id = oi.product_id
    WHERE o.order_status = 'delivered'
      AND p.product_category_name IS NOT NULL AND p.product_category_name <> ''
)
SELECT count(*) AS empty_having_cnt FROM (
    SELECT cs.category
    FROM cat_state cs
    JOIN target_states t ON t.state = cs.state
    GROUP BY cs.category
    HAVING count(DISTINCT cs.state) = (SELECT count(*) FROM target_states)) h;

-- 8*. Продавцы, которые продавали покупателям каждого из трёх штатов
WITH target_states(state) AS (
    VALUES ('AL'), ('SE'), ('BA')
), seller_state AS (
    SELECT DISTINCT oi.seller_id, c.customer_state AS state
    FROM olist.order_items oi
    JOIN olist.orders o    ON o.order_id = oi.order_id
    JOIN olist.customers c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
), sellers AS (
    SELECT DISTINCT seller_id FROM seller_state
)
SELECT s.seller_id
FROM sellers s
WHERE NOT EXISTS (
    SELECT 1 FROM target_states t
    WHERE NOT EXISTS (
        SELECT 1 FROM seller_state ss
        WHERE ss.seller_id = s.seller_id AND ss.state = t.state))
ORDER BY s.seller_id;
