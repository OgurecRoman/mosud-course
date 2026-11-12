-- 1. Запросы A и B: count(*) и count(DISTINCT product_id)

-- Запрос A (мультимножество: товар повторяется, если его покупали несколько раз)
SELECT oi.product_id
FROM olist.order_items oi
JOIN olist.orders o    ON o.order_id = oi.order_id
JOIN olist.customers c ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered'
  AND c.customer_state = 'MA';

-- Запрос B
SELECT oi.product_id
FROM olist.order_items oi
JOIN olist.orders o    ON o.order_id = oi.order_id
JOIN olist.customers c ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered'
  AND c.customer_state = 'PI';

-- Мощности: count(*) - размер мультимножества, count(DISTINCT) - размер множества
SELECT 'A' AS set_name,
       count(*) AS cnt_all,
       count(DISTINCT oi.product_id) AS cnt_distinct
FROM olist.order_items oi
JOIN olist.orders o    ON o.order_id = oi.order_id
JOIN olist.customers c ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered' AND c.customer_state = 'MA'
UNION ALL
SELECT 'B',
       count(*),
       count(DISTINCT oi.product_id)
FROM olist.order_items oi
JOIN olist.orders o    ON o.order_id = oi.order_id
JOIN olist.customers c ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered' AND c.customer_state = 'PI';

-- Для дальнейших запросов удобнее временные представления (в схеме pg_temp,
-- исходные данные не меняются).
CREATE OR REPLACE TEMP VIEW set_a AS
SELECT oi.product_id
FROM olist.order_items oi
JOIN olist.orders o    ON o.order_id = oi.order_id
JOIN olist.customers c ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered' AND c.customer_state = 'MA';

CREATE OR REPLACE TEMP VIEW set_b AS
SELECT oi.product_id
FROM olist.order_items oi
JOIN olist.orders o    ON o.order_id = oi.order_id
JOIN olist.customers c ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered' AND c.customer_state = 'PI';

-- 2. A ∪ B: UNION и UNION ALL

-- UNION удаляет дубликаты
SELECT count(*) AS union_cnt
FROM (SELECT product_id FROM set_a
      UNION
      SELECT product_id FROM set_b) u;

-- UNION ALL сохраняет все строки
SELECT count(*) AS union_all_cnt
FROM (SELECT product_id FROM set_a
      UNION ALL
      SELECT product_id FROM set_b) u;

-- Разница в числе строк = дубликаты внутри A, внутри B и товары, общие для A и B
SELECT (SELECT count(*) FROM (SELECT product_id FROM set_a UNION ALL SELECT product_id FROM set_b) x)
     - (SELECT count(*) FROM (SELECT product_id FROM set_a UNION     SELECT product_id FROM set_b) y)
       AS removed_by_union;

-- 3. A ∩ B: INTERSECT

SELECT count(*) AS intersect_cnt
FROM (SELECT product_id FROM set_a
      INTERSECT
      SELECT product_id FROM set_b) i;

SELECT product_id FROM set_a
INTERSECT
SELECT product_id FROM set_b
ORDER BY product_id;

-- Вариант INTERSECT ALL
SELECT count(*) AS intersect_all_cnt
FROM (SELECT product_id FROM set_a
      INTERSECT ALL
      SELECT product_id FROM set_b) i;

-- 4. Разности: A − B и B − A

SELECT count(*) AS a_minus_b_cnt
FROM (SELECT product_id FROM set_a
      EXCEPT
      SELECT product_id FROM set_b) d;

SELECT count(*) AS b_minus_a_cnt
FROM (SELECT product_id FROM set_b
      EXCEPT
      SELECT product_id FROM set_a) d;

-- EXCEPT ALL
SELECT count(*) AS a_minus_all_b_cnt
FROM (SELECT product_id FROM set_a
      EXCEPT ALL
      SELECT product_id FROM set_b) d;

-- 5. Коммутативность ∪ и ∩ на данных

SELECT
  (SELECT count(*) FROM ((SELECT product_id FROM set_a UNION SELECT product_id FROM set_b)
                         EXCEPT
                         (SELECT product_id FROM set_b UNION SELECT product_id FROM set_a)) t1)
    AS union_diff_ab_ba,
  (SELECT count(*) FROM ((SELECT product_id FROM set_b UNION SELECT product_id FROM set_a)
                         EXCEPT
                         (SELECT product_id FROM set_a UNION SELECT product_id FROM set_b)) t2)
    AS union_diff_ba_ab,
  (SELECT count(*) FROM ((SELECT product_id FROM set_a INTERSECT SELECT product_id FROM set_b)
                         EXCEPT
                         (SELECT product_id FROM set_b INTERSECT SELECT product_id FROM set_a)) t3)
    AS intersect_diff_ab_ba,
  (SELECT count(*) FROM ((SELECT product_id FROM set_b INTERSECT SELECT product_id FROM set_a)
                         EXCEPT
                         (SELECT product_id FROM set_a INTERSECT SELECT product_id FROM set_b)) t4)
    AS intersect_diff_ba_ab;
-- A ∪ B = B ∪ A и A ∩ B = B ∩ A

-- 6. Некоммутативность разности

-- A − B и B − A
SELECT
  (SELECT count(*) FROM (SELECT product_id FROM set_a EXCEPT SELECT product_id FROM set_b) x) AS a_minus_b,
  (SELECT count(*) FROM (SELECT product_id FROM set_b EXCEPT SELECT product_id FROM set_a) y) AS b_minus_a;

-- Множества A − B и B − A не совпадают
SELECT count(*) AS common_of_both_differences
FROM ((SELECT product_id FROM set_a EXCEPT SELECT product_id FROM set_b)
      INTERSECT
      (SELECT product_id FROM set_b EXCEPT SELECT product_id FROM set_a)) z;

-- 7. Пересечение без INTERSECT, через EXISTS

SELECT count(*) AS exists_intersect_cnt
FROM (SELECT DISTINCT a.product_id
      FROM set_a a
      WHERE EXISTS (SELECT 1 FROM set_b b WHERE b.product_id = a.product_id)) e;

-- результат EXISTS совпадает с INTERSECT
SELECT count(*) AS mismatch_cnt
FROM (
  (SELECT DISTINCT a.product_id
   FROM set_a a
   WHERE EXISTS (SELECT 1 FROM set_b b WHERE b.product_id = a.product_id))
  EXCEPT
  (SELECT product_id FROM set_a INTERSECT SELECT product_id FROM set_b)
) m1
UNION ALL
SELECT count(*)
FROM (
  (SELECT product_id FROM set_a INTERSECT SELECT product_id FROM set_b)
  EXCEPT
  (SELECT DISTINCT a.product_id
   FROM set_a a
   WHERE EXISTS (SELECT 1 FROM set_b b WHERE b.product_id = a.product_id))
) m2;

-- 8. Намеренное появление дубликатов

-- Без DISTINCT
SELECT count(*) AS exists_without_distinct_cnt
FROM (SELECT a.product_id
      FROM set_a a
      WHERE EXISTS (SELECT 1 FROM set_b b WHERE b.product_id = a.product_id)) e;

-- Какие товары повторяются
SELECT a.product_id, count(*) AS times
FROM set_a a
WHERE EXISTS (SELECT 1 FROM set_b b WHERE b.product_id = a.product_id)
GROUP BY a.product_id
HAVING count(*) > 1
ORDER BY times DESC, a.product_id;

-- Объединение через UNION ALL вместо UNION
SELECT product_id, count(*) AS times
FROM (SELECT product_id FROM set_a
      UNION ALL
      SELECT product_id FROM set_b) u
GROUP BY product_id
HAVING count(*) > 1
ORDER BY times DESC, product_id
LIMIT 10;

-- 9. Множество или мультимножество
-- Возвращают МНОЖЕСТВО: SELECT DISTINCT, UNION, INTERSECT, EXCEPT (без ALL).
-- Могут вернуть МУЛЬТИМНОЖЕСТВО: SELECT без DISTINCT, UNION ALL, INTERSECT ALL, EXCEPT ALL, JOIN, EXISTS без DISTINCT.
