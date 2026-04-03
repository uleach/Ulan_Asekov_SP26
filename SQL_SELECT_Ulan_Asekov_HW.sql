/* DVD Rental Data Analysis - Part 1
  Logic: 
  - Revenue after March 2017 starts from 2017-04-01.
  - Using public schema as required.
  - COALESCE used on address2 for data integrity.
*/

-- 1. Animation movies 2017-2019, rate > 1
-- JOIN variant (Recommended)
SELECT f.title
FROM public.film f
INNER JOIN public.film_category fc ON f.film_id = fc.film_id
INNER JOIN public.category c ON fc.category_id = c.category_id
WHERE c.name = 'Animation' 
  AND f.release_year BETWEEN 2017 AND 2019 
  AND f.rental_rate > 1
ORDER BY f.title;

-- CTE variant
WITH anim AS (
    SELECT fc.film_id FROM public.film_category fc
    JOIN public.category c ON fc.category_id = c.category_id
    WHERE c.name = 'Animation'
)
SELECT f.title FROM public.film f
JOIN anim ON f.film_id = anim.film_id
WHERE f.release_year BETWEEN 2017 AND 2019 AND f.rental_rate > 1;

-- Subquery variant
SELECT title FROM public.film 
WHERE release_year BETWEEN 2017 AND 2019 AND rental_rate > 1
AND film_id IN (SELECT film_id FROM public.film_category WHERE category_id = 2); 
-- Note: category_id 2 is Animation, but usually we join name to avoid hardcoding IDs.


-- 2. Revenue by store after March 2017
-- CTE variant (Recommended for finance reports)
WITH store_rev AS (
    SELECT s.store_id, SUM(p.amount) as rev
    FROM public.payment p
    JOIN public.rental r ON p.rental_id = r.rental_id
    JOIN public.inventory r ON r.inventory_id = i.inventory_id
    WHERE p.payment_date >= '2017-04-01'
    GROUP BY s.store_id
)
SELECT a.address || ' ' || COALESCE(a.address2, '') as full_address, sr.rev
FROM store_rev sr
JOIN public.store st ON sr.store_id = st.store_id
JOIN public.address a ON st.address_id = a.address_id;

-- JOIN variant
SELECT a.address || ' ' || COALESCE(a.address2, '') as address, SUM(p.amount) as revenue
FROM public.payment p
JOIN public.staff s ON p.staff_id = s.staff_id
JOIN public.store st ON s.store_id = st.store_id
JOIN public.address a ON st.address_id = a.address_id
WHERE p.payment_date >= '2017-04-01'
GROUP BY store_id;

-- Subquery variant
SELECT (SELECT address FROM public.address WHERE address_id = st.address_id) as addr,
       (SELECT SUM(amount) FROM public.payment p JOIN public.staff s ON p.staff_id = s.staff_id WHERE s.store_id = st.store_id AND p.payment_date >= '2017-04-01') as rev
FROM public.store st;


-- 3. Top-5 actors since 2015
-- JOIN variant
SELECT a.first_name, a.last_name, COUNT(fa.film_id) as movie_count
FROM public.actor a
JOIN public.film_actor fa ON a.actor_id = fa.actor_id
JOIN public.film f ON fa.film_id = f.film_id
WHERE f.release_year >= 2015
GROUP BY a.actor_id, a.first_name, a.last_name
ORDER BY movie_count DESC
LIMIT 5;

-- CTE variant
WITH acts AS (
    SELECT actor_id, COUNT(film_id) as total FROM public.film_actor fa
    JOIN public.film f ON fa.film_id = f.film_id
    WHERE f.release_year >= 2015
    GROUP BY actor_id
)
SELECT first_name, last_name, total FROM acts
JOIN public.actor a ON a.actor_id = acts.actor_id
ORDER BY total DESC LIMIT 5;

-- Subquery variant
SELECT a.first_name, a.last_name, 
    (SELECT COUNT(*) FROM public.film_actor fa 
     JOIN public.film f ON f.film_id = fa.film_id 
     WHERE fa.actor_id = a.actor_id AND f.release_year >= 2015) as movies
FROM public.actor a
ORDER BY movies DESC LIMIT 5;


-- 4. Genre trends (Drama, Travel, Documentary)
-- This is a pivot query using CASE WHEN.
SELECT 
    f.release_year,
    SUM(CASE WHEN c.name = 'Drama' THEN 1 ELSE 0 END) AS drama_count,
    SUM(CASE WHEN c.name = 'Travel' THEN 1 ELSE 0 END) AS travel_count,
    SUM(CASE WHEN c.name = 'Documentary' THEN 1 ELSE 0 END) AS doc_count
FROM public.film f
JOIN public.film_category fc ON f.film_id = fc.film_id
JOIN public.category c ON fc.category_id = c.category_id
WHERE LOWER (c.name) IN ('drama', 'travel', 'documentary')
GROUP BY f.release_year
ORDER BY f.release_year DESC;

-- Part 2.1: Top 3 employees by revenue in 2017
-- Includes the last store they were associated with via their most recent payment.
SELECT 
    s.first_name, 
    s.last_name, 
    SUM(p.amount) AS total_revenue,
    (SELECT st.store_id 
     FROM public.payment p2 
     JOIN public.staff s2 ON p2.staff_id = s2.staff_id
     JOIN public.store st ON s2.store_id = st.store_id
     WHERE s2.staff_id = s.staff_id
     ORDER BY p2.payment_date DESC LIMIT 1) AS last_store_id
FROM public.payment p
JOIN public.staff s ON p.staff_id = s.staff_id
WHERE p.payment_date BETWEEN '2017-01-01' AND '2017-12-31'
GROUP BY s.staff_id, s.first_name, s.last_name
ORDER BY total_revenue DESC
LIMIT 3;

-- Part 2.2: Top 5 most rented movies and expected audience age
SELECT 
    f.title, 
    COUNT(r.rental_id) AS rental_count,
    CASE 
        WHEN f.rating = 'G' THEN 'All Ages'
        WHEN f.rating = 'PG' THEN '8+'
        WHEN f.rating = 'PG-13' THEN '13+'
        WHEN f.rating = 'R' THEN '17+'
        WHEN f.rating = 'NC-17' THEN '18+'
        ELSE 'Unknown'
    END AS expected_age_group
FROM public.film f
JOIN public.inventory i ON f.film_id = i.film_id
JOIN public.rental r ON i.inventory_id = r.inventory_id
GROUP BY f.film_id, f.title, f.rating
ORDER BY rental_count DESC
LIMIT 5;

-- Part 3 V1: Gap between latest release and current year
SELECT 
    a.first_name, 
    a.last_name, 
    (EXTRACT(YEAR FROM CURRENT_DATE) - MAX(f.release_year)) AS years_since_last_release
FROM public.actor a
JOIN public.film_actor fa ON a.actor_id = fa.actor_id
JOIN public.film f ON fa.film_id = f.film_id
GROUP BY a.actor_id, a.first_name, a.last_name
ORDER BY years_since_last_release DESC;

-- Part 3 V2: Maximum gap between sequential films per actor (using self-join)
SELECT 
    res.first_name, 
    res.last_name, 
    MAX(res.gap) AS longest_gap_years
FROM (
    SELECT 
        a.first_name, 
        a.last_name, 
        f1.release_year AS current_film,
        MIN(f2.release_year) - f1.release_year AS gap
    FROM public.actor a
    JOIN public.film_actor fa1 ON a.actor_id = fa1.actor_id
    JOIN public.film f1 ON fa1.film_id = f1.film_id
    JOIN public.film_actor fa2 ON a.actor_id = fa2.actor_id
    JOIN public.film f2 ON fa2.film_id = f2.film_id
    WHERE f2.release_year > f1.release_year
    GROUP BY a.actor_id, a.first_name, a.last_name, f1.release_year
) AS res
GROUP BY res.first_name, res.last_name
ORDER BY longest_gap_years DESC;

