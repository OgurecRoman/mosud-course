SELECT 'customers' AS table_name, count(*) FROM olist.customers
UNION ALL SELECT 'orders', count(*) FROM olist.orders
UNION ALL SELECT 'order_items', count(*) FROM olist.order_items;

SELECT count(*) AS orphan_items
FROM olist.order_items oi
LEFT JOIN olist.orders o ON o.order_id = oi.order_id
WHERE o.order_id IS NULL;


ANALYZE;
