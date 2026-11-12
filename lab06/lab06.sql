-- 1. Основное решение: скалярный подзапрос

SELECT t.customer_unique_id, t.orders_cnt, t.total_spent
FROM (
    SELECT c.customer_unique_id,
           count(DISTINCT o.order_id) AS orders_cnt,
           sum(p.payment_value)       AS total_spent
    FROM olist.customers c
    JOIN olist.orders o         ON o.customer_id = c.customer_id AND o.order_status = 'delivered'
    JOIN olist.order_payments p ON p.order_id = o.order_id
    WHERE EXISTS (
        SELECT 1
        FROM olist.customers c2
        JOIN olist.orders o2 ON o2.customer_id = c2.customer_id AND o2.order_status = 'delivered'
        WHERE c2.customer_unique_id = c.customer_unique_id
          AND o2.order_id <> o.order_id)
    GROUP BY c.customer_unique_id
) t
WHERE t.total_spent > (
    SELECT avg(s.total_spent)
    FROM (
        SELECT c.customer_unique_id, sum(p.payment_value) AS total_spent
        FROM olist.customers c
        JOIN olist.orders o         ON o.customer_id = c.customer_id AND o.order_status = 'delivered'
        JOIN olist.order_payments p ON p.order_id = o.order_id
        WHERE EXISTS (
            SELECT 1
            FROM olist.customers c2
            JOIN olist.orders o2 ON o2.customer_id = c2.customer_id AND o2.order_status = 'delivered'
            WHERE c2.customer_unique_id = c.customer_unique_id
              AND o2.order_id <> o.order_id)
        GROUP BY c.customer_unique_id) s)
ORDER BY t.total_spent DESC, t.customer_unique_id;

-- 2. Альтернатива: CTE с предварительной агрегацией и JOIN
WITH order_spend AS (
    SELECT c.customer_unique_id, o.order_id, sum(p.payment_value) AS order_total
    FROM olist.customers c
    JOIN olist.orders o         ON o.customer_id = c.customer_id AND o.order_status = 'delivered'
    JOIN olist.order_payments p ON p.order_id = o.order_id
    GROUP BY c.customer_unique_id, o.order_id
), buyer_spend AS (
    SELECT customer_unique_id,
           count(*)         AS orders_cnt,
           sum(order_total) AS total_spent
    FROM order_spend
    GROUP BY customer_unique_id
), repeat_buyers AS (
    SELECT * FROM buyer_spend WHERE orders_cnt >= 2
), avg_spend AS (
    SELECT avg(total_spent) AS avg_total FROM repeat_buyers
)
SELECT rb.customer_unique_id, rb.orders_cnt, rb.total_spent
FROM repeat_buyers rb
JOIN avg_spend a ON rb.total_spent > a.avg_total
ORDER BY rb.total_spent DESC, rb.customer_unique_id;

-- 3. Проверка EXCEPT в обе стороны
WITH r1 AS (
    SELECT t.customer_unique_id, t.orders_cnt, t.total_spent
    FROM (
        SELECT c.customer_unique_id,
               count(DISTINCT o.order_id) AS orders_cnt,
               sum(p.payment_value)       AS total_spent
        FROM olist.customers c
        JOIN olist.orders o         ON o.customer_id = c.customer_id AND o.order_status = 'delivered'
        JOIN olist.order_payments p ON p.order_id = o.order_id
        WHERE EXISTS (
            SELECT 1
            FROM olist.customers c2
            JOIN olist.orders o2 ON o2.customer_id = c2.customer_id AND o2.order_status = 'delivered'
            WHERE c2.customer_unique_id = c.customer_unique_id
              AND o2.order_id <> o.order_id)
        GROUP BY c.customer_unique_id
    ) t
    WHERE t.total_spent > (
        SELECT avg(s.total_spent)
        FROM (
            SELECT c.customer_unique_id, sum(p.payment_value) AS total_spent
            FROM olist.customers c
            JOIN olist.orders o         ON o.customer_id = c.customer_id AND o.order_status = 'delivered'
            JOIN olist.order_payments p ON p.order_id = o.order_id
            WHERE EXISTS (
                SELECT 1
                FROM olist.customers c2
                JOIN olist.orders o2 ON o2.customer_id = c2.customer_id AND o2.order_status = 'delivered'
                WHERE c2.customer_unique_id = c.customer_unique_id
                  AND o2.order_id <> o.order_id)
            GROUP BY c.customer_unique_id) s)
), order_spend AS (
    SELECT c.customer_unique_id, o.order_id, sum(p.payment_value) AS order_total
    FROM olist.customers c
    JOIN olist.orders o         ON o.customer_id = c.customer_id AND o.order_status = 'delivered'
    JOIN olist.order_payments p ON p.order_id = o.order_id
    GROUP BY c.customer_unique_id, o.order_id
), buyer_spend AS (
    SELECT customer_unique_id,
           count(*)         AS orders_cnt,
           sum(order_total) AS total_spent
    FROM order_spend
    GROUP BY customer_unique_id
), repeat_buyers AS (
    SELECT * FROM buyer_spend WHERE orders_cnt >= 2
), avg_spend AS (
    SELECT avg(total_spent) AS avg_total FROM repeat_buyers
), r2 AS (
    SELECT rb.customer_unique_id, rb.orders_cnt, rb.total_spent
    FROM repeat_buyers rb
    JOIN avg_spend a ON rb.total_spent > a.avg_total
)
SELECT 'cnt r1 / r2' AS check_name,
       (SELECT count(*) FROM r1) AS v1,
       (SELECT count(*) FROM r2) AS v2
UNION ALL
SELECT 'r1 EXCEPT r2 / r2 EXCEPT r1',
       (SELECT count(*) FROM (SELECT * FROM r1 EXCEPT SELECT * FROM r2) a),
       (SELECT count(*) FROM (SELECT * FROM r2 EXCEPT SELECT * FROM r1) b);

-- 4. Демонстрация ALL: повторный покупатель с максимальными расходами
WITH order_spend AS (
    SELECT c.customer_unique_id, o.order_id, sum(p.payment_value) AS order_total
    FROM olist.customers c
    JOIN olist.orders o         ON o.customer_id = c.customer_id AND o.order_status = 'delivered'
    JOIN olist.order_payments p ON p.order_id = o.order_id
    GROUP BY c.customer_unique_id, o.order_id
), repeat_buyers AS (
    SELECT customer_unique_id, count(*) AS orders_cnt, sum(order_total) AS total_spent
    FROM order_spend
    GROUP BY customer_unique_id
    HAVING count(*) >= 2
)
SELECT customer_unique_id, orders_cnt, total_spent
FROM repeat_buyers
WHERE total_spent >= ALL (SELECT total_spent FROM repeat_buyers);

-- 5. Демонстрация ANY: расходы выше хотя бы одного из порогов (эквивалентно > минимального порога)
WITH order_spend AS (
    SELECT c.customer_unique_id, o.order_id, sum(p.payment_value) AS order_total
    FROM olist.customers c
    JOIN olist.orders o         ON o.customer_id = c.customer_id AND o.order_status = 'delivered'
    JOIN olist.order_payments p ON p.order_id = o.order_id
    GROUP BY c.customer_unique_id, o.order_id
), repeat_buyers AS (
    SELECT customer_unique_id, count(*) AS orders_cnt, sum(order_total) AS total_spent
    FROM order_spend
    GROUP BY customer_unique_id
    HAVING count(*) >= 2
)
SELECT count(*) AS above_any_threshold
FROM repeat_buyers
WHERE total_spent > ANY (VALUES (1000::numeric), (2000::numeric), (5000::numeric));

-- 6. ALL и NULL: при NULL в подзапросе условие не становится истинным
SELECT 10 > ALL (VALUES (1), (2))       AS no_null,
       10 > ALL (VALUES (1), (NULL))    AS with_null,
       10 > ANY (VALUES (1), (NULL))    AS any_with_null;
