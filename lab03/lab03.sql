-- 1. Исходное отношение и атрибуты
-- Отношение: olist.products
-- Атрибуты: product_id, product_category_name, product_length_cm, product_height_cm, product_width_cm

-- 2. Выражение реляционной алгебры
-- π[product_id, category, length, height, width](
--     σ[category IS NOT NULL ∧ length·height·width > 20000](
--         ρ[p](products)))

-- 3. Реализация в SQL
SELECT p.product_id,
       p.product_category_name AS category,
       p.product_length_cm     AS length,
       p.product_height_cm     AS height,
       p.product_width_cm      AS width
FROM olist.products p
WHERE p.product_category_name IS NOT NULL
  AND p.product_length_cm * p.product_height_cm * p.product_width_cm > 20000;

-- Мощность исходного результата
SELECT count(*) AS original_cnt
FROM olist.products p
WHERE p.product_category_name IS NOT NULL
  AND p.product_length_cm * p.product_height_cm * p.product_width_cm > 20000;

-- 4. Разбиение предиката на две последовательные выборки:
-- σ[объём > 20000](σ[category IS NOT NULL](products))
SELECT s2.product_id,
       s2.product_category_name AS category,
       s2.product_length_cm     AS length,
       s2.product_height_cm     AS height,
       s2.product_width_cm      AS width
FROM (SELECT *
      FROM olist.products
      WHERE product_category_name IS NOT NULL) s2
WHERE s2.product_length_cm * s2.product_height_cm * s2.product_width_cm > 20000;

-- Эквивалентность: разности в обе стороны пусты и число строк совпадает
SELECT
  (SELECT count(*) FROM (
     (SELECT p.product_id, p.product_category_name, p.product_length_cm, p.product_height_cm, p.product_width_cm
      FROM olist.products p
      WHERE p.product_category_name IS NOT NULL
        AND p.product_length_cm * p.product_height_cm * p.product_width_cm > 20000)
     EXCEPT ALL
     (SELECT s.product_id, s.product_category_name, s.product_length_cm, s.product_height_cm, s.product_width_cm
      FROM (SELECT * FROM olist.products WHERE product_category_name IS NOT NULL) s
      WHERE s.product_length_cm * s.product_height_cm * s.product_width_cm > 20000)
   ) d1) AS original_minus_split,
  (SELECT count(*) FROM (
     (SELECT s.product_id, s.product_category_name, s.product_length_cm, s.product_height_cm, s.product_width_cm
      FROM (SELECT * FROM olist.products WHERE product_category_name IS NOT NULL) s
      WHERE s.product_length_cm * s.product_height_cm * s.product_width_cm > 20000)
     EXCEPT ALL
     (SELECT p.product_id, p.product_category_name, p.product_length_cm, p.product_height_cm, p.product_width_cm
      FROM olist.products p
      WHERE p.product_category_name IS NOT NULL
        AND p.product_length_cm * p.product_height_cm * p.product_width_cm > 20000)
   ) d2) AS split_minus_original;

-- 5. Вариант с ранним исключением ненужных столбцов:
SELECT t.product_id, t.category, t.length, t.height, t.width
FROM (SELECT product_id,
             product_category_name AS category,
             product_length_cm     AS length,
             product_height_cm     AS height,
             product_width_cm      AS width
      FROM olist.products) t
WHERE t.category IS NOT NULL
  AND t.length * t.height * t.width > 20000;

-- Сравнение с исходным вариантом
SELECT count(*) AS mismatch_cnt FROM (
  (SELECT product_id, product_category_name, product_length_cm, product_height_cm, product_width_cm
   FROM olist.products
   WHERE product_category_name IS NOT NULL
     AND product_length_cm * product_height_cm * product_width_cm > 20000)
  EXCEPT ALL
  (SELECT t.product_id, t.category, t.length, t.height, t.width
   FROM (SELECT product_id, product_category_name AS category, product_length_cm AS length,
                product_height_cm AS height, product_width_cm AS width
         FROM olist.products) t
   WHERE t.category IS NOT NULL AND t.length * t.height * t.width > 20000)
) m1
UNION ALL
SELECT count(*) FROM (
  (SELECT t.product_id, t.category, t.length, t.height, t.width
   FROM (SELECT product_id, product_category_name AS category, product_length_cm AS length,
                product_height_cm AS height, product_width_cm AS width
         FROM olist.products) t
   WHERE t.category IS NOT NULL AND t.length * t.height * t.width > 20000)
  EXCEPT ALL
  (SELECT product_id, product_category_name, product_length_cm, product_height_cm, product_width_cm
   FROM olist.products
   WHERE product_category_name IS NOT NULL
     AND product_length_cm * product_height_cm * product_width_cm > 20000)
) m2;

-- 6. Дубликаты в проекции
SELECT count(*) AS cnt_all,
       (SELECT count(*) FROM (SELECT DISTINCT product_id, product_category_name, product_length_cm,
                                     product_height_cm, product_width_cm
                              FROM olist.products
                              WHERE product_category_name IS NOT NULL
                                AND product_length_cm * product_height_cm * product_width_cm > 20000) x) AS cnt_distinct
FROM olist.products
WHERE product_category_name IS NOT NULL
  AND product_length_cm * product_height_cm * product_width_cm > 20000;

-- Для сравнения: без product_id дубликаты появляются
SELECT count(*) AS cnt_all_without_pk,
       (SELECT count(*) FROM (SELECT DISTINCT product_category_name, product_length_cm,
                                     product_height_cm, product_width_cm
                              FROM olist.products
                              WHERE product_category_name IS NOT NULL
                                AND product_length_cm * product_height_cm * product_width_cm > 20000) y) AS cnt_distinct_without_pk
FROM olist.products
WHERE product_category_name IS NOT NULL
  AND product_length_cm * product_height_cm * product_width_cm > 20000;
