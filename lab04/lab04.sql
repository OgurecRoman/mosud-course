-- 1. Основной запрос: одна строка на доставленный заказ
WITH it AS (            -- items + sellers
    SELECT oi.order_id,
           count(*)                         AS n_items,
           sum(oi.price)                    AS items_sum,
           sum(oi.freight_value)            AS freight_sum,
           count(DISTINCT oi.seller_id)     AS n_sellers,
           string_agg(DISTINCT s.seller_state, ',' ORDER BY s.seller_state) AS seller_states
    FROM olist.order_items oi
    JOIN olist.sellers s ON s.seller_id = oi.seller_id
    GROUP BY oi.order_id
), pay AS (             -- payments
    SELECT order_id,
           count(*)           AS n_payments,
           sum(payment_value) AS paid_sum
    FROM olist.order_payments
    GROUP BY order_id
), rev AS (             -- reviews
    SELECT order_id,
           count(*)          AS n_reviews,
           avg(review_score) AS avg_score
    FROM olist.order_reviews
    GROUP BY order_id
)
SELECT o.order_id,
       c.customer_state,
       c.customer_city,
       it.n_items, it.items_sum, it.freight_sum, it.n_sellers, it.seller_states,
       pay.n_payments, pay.paid_sum,
       rev.n_reviews, round(rev.avg_score, 2) AS avg_score
FROM olist.orders o
JOIN olist.customers c ON c.customer_id = o.customer_id      -- N:1
LEFT JOIN it  ON it.order_id  = o.order_id                   -- 1:1 после агрегации
LEFT JOIN pay ON pay.order_id = o.order_id                   -- 1:1 после агрегации
LEFT JOIN rev ON rev.order_id = o.order_id                   -- 1:1 после агрегации
WHERE o.order_status = 'delivered'
ORDER BY o.order_id
LIMIT 10;

-- Контроль кратности: число строк паспорта должно равняться числу delivered-заказов
SELECT
  (SELECT count(*) FROM olist.orders WHERE order_status = 'delivered') AS delivered_orders,
  (SELECT count(*)
   FROM olist.orders o
   JOIN olist.customers c ON c.customer_id = o.customer_id
   LEFT JOIN (SELECT order_id FROM olist.order_items    GROUP BY order_id) it  ON it.order_id  = o.order_id
   LEFT JOIN (SELECT order_id FROM olist.order_payments GROUP BY order_id) pay ON pay.order_id = o.order_id
   LEFT JOIN (SELECT order_id FROM olist.order_reviews  GROUP BY order_id) rev ON rev.order_id = o.order_id
   WHERE o.order_status = 'delivered') AS passport_rows;

-- 2. Кратности связей
-- orders -> customers : N:1
-- orders -> items : 1:N
-- items -> sellers : N:1
-- orders -> payments : 1:N
-- orders -> reviews : 1:N

-- 3. LEFT JOIN: сохраняем заказы без платежей / без отзывов
SELECT count(*)                                  AS delivered_orders,
       count(pay.order_id)                       AS with_payments,
       count(rev.order_id)                       AS with_reviews,
       count(*) - count(pay.order_id)            AS without_payments,
       count(*) - count(rev.order_id)            AS without_reviews
FROM olist.orders o
LEFT JOIN (SELECT order_id FROM olist.order_payments GROUP BY order_id) pay ON pay.order_id = o.order_id
LEFT JOIN (SELECT order_id FROM olist.order_reviews  GROUP BY order_id) rev ON rev.order_id = o.order_id
WHERE o.order_status = 'delivered';

-- 4. Антисоединение: заказы без отзыва

-- Вариант 1
SELECT count(*) AS no_review_left_join
FROM olist.orders o
LEFT JOIN olist.order_reviews r ON r.order_id = o.order_id
WHERE r.order_id IS NULL;

-- Вариант 2
SELECT count(*) AS no_review_not_exists
FROM olist.orders o
WHERE NOT EXISTS (SELECT 1 FROM olist.order_reviews r WHERE r.order_id = o.order_id);

-- 5. Ошибочный JOIN: items x payments напрямую по order_id
SELECT count(*)         AS rows_wrong,
       sum(oi.price)    AS price_sum_wrong
FROM olist.orders o
JOIN olist.order_items oi    ON oi.order_id = o.order_id
JOIN olist.order_payments op ON op.order_id = o.order_id
WHERE o.order_status = 'delivered';

-- Эталон: items без payments
SELECT count(*)         AS rows_correct,
       sum(oi.price)    AS price_sum_correct
FROM olist.orders o
JOIN olist.order_items oi ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered';

-- 6. Исправление: предварительная агрегация до одной строки на заказ
SELECT count(*)         AS rows_fixed,
       sum(it.items_sum) AS price_sum_fixed,
       sum(pay.paid_sum) AS paid_sum
FROM olist.orders o
JOIN (SELECT order_id, sum(price) AS items_sum
      FROM olist.order_items GROUP BY order_id) it  ON it.order_id  = o.order_id
JOIN (SELECT order_id, sum(payment_value) AS paid_sum
      FROM olist.order_payments GROUP BY order_id) pay ON pay.order_id = o.order_id
WHERE o.order_status = 'delivered';

-- 7. Композиция реляционной алгебры для основного запроса
-- π[order_id, customer_state, customer_city, n_items, items_sum, freight_sum,
--   n_sellers, seller_states, n_payments, paid_sum, n_reviews, avg_score](
--     σ[order_status = 'delivered'](
--         ( ( ( orders ⋈[customer_id] customers )
--               ⟕[order_id] γ[order_id; count, sum, ...]( order_items ⋈[seller_id] sellers ) )
--               ⟕[order_id] γ[order_id; count, sum]( order_payments ) )
--               ⟕[order_id] γ[order_id; count, avg]( order_reviews ) ) )
-- где ⋈ - эквисоединение, ⟕ - левое внешнее соединение, γ - группировка с агрегатами.
