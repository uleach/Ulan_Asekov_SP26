  SQL_DML_HW - Task 1
  Movies: Lost in Translation, Groundhog Day, In the Mood for Love

-- 1. Add 3 favorite movies to the 'film' table
-- Justification: Using subqueries for language_id ensures data integrity. 
-- TRANSACTION LOGIC: A separate transaction is used here to ensure that all 3 films 
-- are added as a single atomic unit. If one fails, none are added.
-- ROLLBACK: If the transaction fails before COMMIT, no data is changed. 
-- Once COMMIT is issued, a rollback is no longer possible.
-- DUPLICATES: Avoided using ON CONFLICT (title) DO NOTHING.
-- ON CONFLICT prevents duplicates if the script is rerunnable.
BEGIN;

INSERT INTO public.film (title, release_year, language_id, rental_duration, rental_rate, last_update)
SELECT 'Lost in Translation', 2003, language_id, 7, 4.99, CURRENT_DATE FROM public.language WHERE name = 'English'
UNION ALL
SELECT 'Groundhog Day', 1993, language_id, 14, 9.99, CURRENT_DATE FROM public.language WHERE name = 'English'
UNION ALL
SELECT 'In the Mood for Love', 2000, language_id, 21, 19.99, CURRENT_DATE FROM public.language WHERE name = 'English'
ON CONFLICT (title) DO NOTHING
RETURNING *;

COMMIT;
/* Transaction Logic: Separate transaction used for the core film data. 
   If the language 'English' were missing, the entire insert would fail, 
   preserving referential integrity. Rollback is possible before COMMIT.
*/


-- 2. Add real actors to the 'actor' table
-- Justification: Using ON CONFLICT (first_name, last_name) to avoid duplicates.
BEGIN;

INSERT INTO public.actor (first_name, last_name, last_update)
VALUES 
('Bill', 'Murray', CURRENT_DATE),
('Scarlett', 'Johansson', CURRENT_DATE),
('Andie', 'MacDowell', CURRENT_DATE),
('Tony', 'Leung', CURRENT_DATE),
('Maggie', 'Cheung', CURRENT_DATE),
('Giovanni', 'Ribisi', CURRENT_DATE)
ON CONFLICT (first_name, last_name) DO NOTHING
RETURNING *;

COMMIT;


-- 3. Link actors to movies in 'film_actor'
-- Justification: Using SELECT for IDs instead of hardcoding.
BEGIN;

INSERT INTO public.film_actor (actor_id, film_id, last_update)
SELECT a.actor_id, f.film_id, CURRENT_DATE
FROM public.actor a, public.film f
WHERE (a.first_name = 'Bill' AND a.last_name = 'Murray' AND f.title IN ('Lost in Translation', 'Groundhog Day'))
   OR (a.first_name = 'Scarlett' AND a.last_name = 'Johansson' AND f.title = 'Lost in Translation')
   OR (a.first_name = 'Andie' AND a.last_name = 'MacDowell' AND f.title = 'Groundhog Day')
   OR (a.first_name = 'Tony' AND a.last_name = 'Leung' AND f.title = 'In the Mood for Love')
   OR (a.first_name = 'Maggie' AND a.last_name = 'Cheung' AND f.title = 'In the Mood for Love')
ON CONFLICT DO NOTHING;

COMMIT;


-- 4. Add movies to Store 1's inventory
BEGIN;

INSERT INTO public.inventory (film_id, store_id, last_update)
SELECT film_id, 1, CURRENT_DATE 
FROM public.film 
WHERE title IN ('Lost in Translation', 'Groundhog Day', 'In the Mood for Love')
ON CONFLICT DO NOTHING;

COMMIT;


-- 5. Alter existing customer with > 43 rentals/payments to your data
-- Justification: Identifies a "heavy user" dynamically.
BEGIN;

UPDATE public.customer
SET first_name = 'Ulan', 
    last_name = 'ASEKOV', 
    email = 'asekov.42@gmail.com',
    last_update = CURRENT_DATE
WHERE customer_id = (
    SELECT c.customer_id 
    FROM public.customer c
    JOIN public.rental r ON c.customer_id = r.customer_id
    JOIN public.payment p ON c.customer_id = p.customer_id
    GROUP BY c.customer_id
    HAVING COUNT(DISTINCT r.rental_id) >= 43 AND COUNT(DISTINCT p.payment_id) >= 43
    LIMIT 1
)
RETURNING *;

COMMIT;


-- 6. Remove records related to you (except Customer and Inventory)
-- Justification: Maintains referential integrity by deleting child records (payment) before parent records (rental).
BEGIN;
-- REFERENTIAL INTEGRITY: We delete from 'payment' then 'rental' to satisfy 
-- Foreign Key constraints. This prevents 'orphaned' rows and data loss

DELETE FROM public.payment 
WHERE customer_id = (SELECT customer_id FROM public.customer WHERE email = 'asekov.42@gmail.com');

DELETE FROM public.rental 
WHERE customer_id = (SELECT customer_id FROM public.customer WHERE email = 'asekov.42@gmail.com');

COMMIT;


-- 7. Rent and Pay for movies (First half of 2017)
BEGIN;

-- Insert Rental
INSERT INTO public.rental (rental_date, inventory_id, customer_id, staff_id, last_update)
SELECT '2017-05-15', i.inventory_id, c.customer_id, 1, CURRENT_DATE
FROM public.inventory i, public.customer c
WHERE i.film_id = (SELECT film_id FROM public.film WHERE title = 'Lost in Translation')
AND c.email = 'asekov.42@gmail.com'
LIMIT 1
RETURNING rental_id;

-- Insert Payment based on that rental
INSERT INTO public.payment (customer_id, staff_id, rental_id, amount, payment_date)
SELECT r.customer_id, r.staff_id, r.rental_id, 4.99, '2017-05-15'
FROM public.rental r
WHERE r.rental_date = '2017-05-15' 
AND r.customer_id = (SELECT customer_id FROM public.customer WHERE email = 'asekov.42@gmail.com');

COMMIT;


-----




