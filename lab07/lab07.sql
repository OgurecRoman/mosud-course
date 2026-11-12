-- 1. Число NULL по необязательным столбцам

SELECT 'orders' AS tbl, count(*) AS total,
       count(*) FILTER (WHERE order_status IS NULL)                  AS order_status,
       count(*) FILTER (WHERE order_purchase_timestamp IS NULL)      AS order_purchase_timestamp,
       count(*) FILTER (WHERE order_approved_at IS NULL)             AS order_approved_at,
       count(*) FILTER (WHERE order_delivered_carrier_date IS NULL)  AS order_delivered_carrier_date,
       count(*) FILTER (WHERE order_delivered_customer_date IS NULL) AS order_delivered_customer_date,
       count(*) FILTER (WHERE order_estimated_delivery_date IS NULL) AS order_estimated_delivery_date
FROM olist.orders;

SELECT 'products' AS tbl, count(*) AS total,
       count(*) FILTER (WHERE product_category_name IS NULL)       AS product_category_name,
       count(*) FILTER (WHERE product_name_lenght IS NULL)         AS product_name_lenght,
       count(*) FILTER (WHERE product_description_lenght IS NULL)  AS product_description_lenght,
       count(*) FILTER (WHERE product_photos_qty IS NULL)          AS product_photos_qty,
       count(*) FILTER (WHERE product_weight_g IS NULL)            AS product_weight_g,
       count(*) FILTER (WHERE product_length_cm IS NULL)           AS product_length_cm,
       count(*) FILTER (WHERE product_height_cm IS NULL)           AS product_height_cm,
       count(*) FILTER (WHERE product_width_cm IS NULL)            AS product_width_cm
FROM olist.products;

SELECT 'order_reviews' AS tbl, count(*) AS total,
       count(*) FILTER (WHERE review_score IS NULL)            AS review_score,
       count(*) FILTER (WHERE review_comment_title IS NULL)    AS review_comment_title,
       count(*) FILTER (WHERE review_comment_message IS NULL)  AS review_comment_message,
       count(*) FILTER (WHERE review_creation_date IS NULL)    AS review_creation_date,
       count(*) FILTER (WHERE review_answer_timestamp IS NULL) AS review_answer_timestamp
FROM olist.order_reviews;

-- Пустые строки вместо NULL в текстовых столбцах
SELECT (SELECT count(*) FROM olist.products WHERE product_category_name = '')       AS empty_category,
       (SELECT count(*) FROM olist.order_reviews WHERE review_comment_title = '')   AS empty_title,
       (SELECT count(*) FROM olist.order_reviews WHERE review_comment_message = '') AS empty_message;

-- 2. COUNT(*) и COUNT(столбца)
SELECT count(*)                                   AS cnt_all,
       count(order_delivered_customer_date)       AS cnt_delivered_date,
       count(*) - count(order_delivered_customer_date) AS diff
FROM olist.orders;

-- Разница по статусам заказов
SELECT order_status,
       count(*) AS cnt_all,
       count(order_delivered_customer_date) AS cnt_delivered_date,
       count(*) - count(order_delivered_customer_date) AS no_date
FROM olist.orders
GROUP BY order_status
ORDER BY no_date DESC, order_status;

-- 3. = NULL и <> NULL не работают
SELECT count(*) AS eq_null FROM olist.orders WHERE order_delivered_customer_date = NULL;
SELECT count(*) AS ne_null FROM olist.orders WHERE order_delivered_customer_date <> NULL;
SELECT count(*) AS is_null FROM olist.orders WHERE order_delivered_customer_date IS NULL;
SELECT count(*) AS is_not_null FROM olist.orders WHERE order_delivered_customer_date IS NOT NULL;

-- 4. IS DISTINCT FROM
SELECT v.a, v.b,
       v.a = v.b                    AS eq,
       v.a <> v.b                   AS ne,
       v.a IS DISTINCT FROM v.b     AS is_distinct,
       v.a IS NOT DISTINCT FROM v.b AS is_not_distinct
FROM (VALUES (1, 1), (1, 2), (1, NULL::int), (NULL::int, 1), (NULL::int, NULL::int)) v(a, b);

-- Применение на данных: заказы, у которых дата доставки отличается от оценочной (в том числе NULL)
SELECT count(*) AS ne_cnt
FROM olist.orders
WHERE order_delivered_customer_date <> order_estimated_delivery_date;

SELECT count(*) AS is_distinct_cnt
FROM olist.orders
WHERE order_delivered_customer_date IS DISTINCT FROM order_estimated_delivery_date;

-- 5. NOT IN и NOT EXISTS с NULL во временной таблице
DROP TABLE IF EXISTS temp_ids;
CREATE TEMP TABLE temp_ids (id text);
INSERT INTO temp_ids
SELECT order_id FROM olist.orders ORDER BY order_id LIMIT 1;
INSERT INTO temp_ids VALUES (NULL);

SELECT * FROM temp_ids;

SELECT count(*) AS not_in_cnt
FROM olist.orders o
WHERE o.order_id NOT IN (SELECT id FROM temp_ids);

SELECT count(*) AS not_exists_cnt
FROM olist.orders o
WHERE NOT EXISTS (SELECT 1 FROM temp_ids t WHERE t.id = o.order_id);

-- NOT IN без NULL в подзапросе
SELECT count(*) AS not_in_without_null_cnt
FROM olist.orders o
WHERE o.order_id NOT IN (SELECT id FROM temp_ids WHERE id IS NOT NULL);

DROP TABLE temp_ids;

-- 6. LEFT JOIN: фильтр в ON и в WHERE
SELECT count(DISTINCT o.order_id) AS orders_filter_in_on
FROM olist.orders o
LEFT JOIN olist.order_reviews r
       ON r.order_id = o.order_id AND r.review_score >= 4;

SELECT count(DISTINCT o.order_id) AS orders_filter_in_where
FROM olist.orders o
LEFT JOIN olist.order_reviews r ON r.order_id = o.order_id
WHERE r.review_score >= 4;

-- Сколько заказов в первом варианте остались без подходящего отзыва
SELECT count(DISTINCT o.order_id) AS orders_without_good_review
FROM olist.orders o
LEFT JOIN olist.order_reviews r
       ON r.order_id = o.order_id AND r.review_score >= 4
WHERE r.order_id IS NULL;

-- 7. COALESCE и NULLIF
SELECT review_id,
       review_score,
       review_comment_message AS raw_text,
       COALESCE(review_comment_message, '(без комментария)') AS coalesce_only,
       COALESCE(NULLIF(review_comment_message, ''), '(без комментария)') AS comment_text
FROM olist.order_reviews
ORDER BY review_id
LIMIT 10;

-- Средняя стоимость доставки на единицу цены: NULLIF защищает от деления на 0
SELECT count(*) AS items_total,
       count(*) FILTER (WHERE price = 0) AS zero_price,
       round(avg(freight_value / NULLIF(price, 0)), 4) AS avg_freight_to_price
FROM olist.order_items;

-- 8. Мини-профиль качества
SELECT 'orders: no delivery date' AS metric,
       count(*) FILTER (WHERE order_delivered_customer_date IS NULL) AS bad_cnt,
       count(*) AS total,
       round(100.0 * count(*) FILTER (WHERE order_delivered_customer_date IS NULL) / count(*), 2) AS share_pct
FROM olist.orders
UNION ALL
SELECT 'products: no category',
       count(*) FILTER (WHERE product_category_name IS NULL OR product_category_name = ''),
       count(*),
       round(100.0 * count(*) FILTER (WHERE product_category_name IS NULL OR product_category_name = '') / count(*), 2)
FROM olist.products
UNION ALL
SELECT 'order_reviews: no comment text',
       count(*) FILTER (WHERE review_comment_message IS NULL OR review_comment_message = ''),
       count(*),
       round(100.0 * count(*) FILTER (WHERE review_comment_message IS NULL OR review_comment_message = '') / count(*), 2)
FROM olist.order_reviews;

-- 9. Естественный NULL и NULL как проблема качества
SELECT order_status, count(*) AS cnt
FROM olist.orders
WHERE order_delivered_customer_date IS NULL
GROUP BY order_status
ORDER BY cnt DESC;

-- Доставленные заказы без даты доставки: NULL там указывает на проблему
SELECT count(*) AS delivered_without_date
FROM olist.orders
WHERE order_status = 'delivered' AND order_delivered_customer_date IS NULL;

-- product_category_name: пропуск у товара, который продаётся, указывает на проблему качества
SELECT count(*) FILTER (WHERE p.product_category_name IS NULL) AS sold_items_null_category,
       count(*) FILTER (WHERE p.product_category_name = '')    AS sold_items_empty_category
FROM olist.order_items oi
JOIN olist.products p ON p.product_id = oi.product_id;
