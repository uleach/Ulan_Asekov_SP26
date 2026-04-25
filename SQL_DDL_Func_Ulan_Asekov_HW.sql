-- creating the core schema because the task said so
CREATE SCHEMA IF NOT EXISTS core;

-- Task 1. View for revenue
/* I used extract(quarter) and extract(year) from current_date. 
  It works dynamically. 
  NOTE: I checked the table, there is no data for 2026 so it 
  returns 0 rows right now. I tested it with 2007 dates 
  in my head and it works. 
*/
CREATE OR REPLACE VIEW sales_revenue_by_category_qtr AS
SELECT
    c.name as cat,
    sum(p.amount) as rev
FROM payment p
join rental r on p.rental_id = r.rental_id
join inventory i on r.inventory_id = i.inventory_id
join film_category fc on i.film_id = fc.film_id
join category c on fc.category_id = c.category_id
WHERE extract(quarter from p.payment_date) = extract(quarter from current_date)
  AND extract(year from p.payment_date) = extract(year from current_date)
GROUP BY c.name
HAVING sum(p.amount) > 0;

-- Test 1: current quarter (returns 0 rows on sample data — expected, no 2026 data)
SELECT * FROM sales_revenue_by_category_qtr;

-- Test 2: verify logic with Q1 2017 data
SELECT c.name as cat, sum(p.amount) as rev
FROM payment p
join rental r on p.rental_id = r.rental_id
join inventory i on r.inventory_id = i.inventory_id
join film_category fc on i.film_id = fc.film_id
join category c on fc.category_id = c.category_id
WHERE extract(quarter from p.payment_date) = 1
  AND extract(year from p.payment_date) = 2017
GROUP BY c.name
HAVING sum(p.amount) > 0;


-- Task 2. Function with parameters
/* I made this so you can put in any year or quarter.
  I added a check for the quarter because it can only be 1 to 4.
*/
CREATE OR REPLACE FUNCTION get_sales_revenue_by_category_qtr(q int, y int)
RETURNS TABLE (c_name text, total_rev numeric) AS $$
BEGIN
    IF q < 1 OR q > 4 THEN
        raise exception 'Invalid quarter passed!';
    END IF;

    RETURN QUERY
    SELECT c.name::text, sum(p.amount)
    FROM payment p
    join rental r on p.rental_id = r.rental_id
    join inventory i on r.inventory_id = i.inventory_id
    join film_category fc on i.film_id = fc.film_id
    join category c on fc.category_id = c.category_id
    WHERE extract(quarter from p.payment_date) = q
      AND extract(year from p.payment_date) = y
    GROUP BY c.name
      HAVING sum(p.amount) > 0;

END;
$$ LANGUAGE plpgsql;

-- Task 3. Popular films
/* I defined popularity as the number of rentals. 
  I used rank() so if there's a tie, both movies show up.
*/
CREATE OR REPLACE FUNCTION core.most_popular_films_by_countries(c_list text[])
RETURNS TABLE(country text, title text, count bigint) AS $$
BEGIN
    RETURN QUERY
    with my_data as (
        select 
            co.country::text as c_name, 
            f.title::text as f_t, 
            count(r.rental_id) as total,
            rank() over (partition by co.country order by count(r.rental_id) desc) as r
        from country co
        join city ci on co.country_id = ci.country_id
        join address a on ci.city_id = a.city_id
        join customer cu on a.address_id = cu.address_id
        join rental r on cu.customer_id = r.customer_id
        join inventory i on r.inventory_id = i.inventory_id
        join film f on i.film_id = f.film_id
        where co.country = any(c_list)
        group by co.country, f.title
    )
    select c_name, f_t, total from my_data where r = 1;
END;
$$ LANGUAGE plpgsql;

-- Task 4. Film search
/* I used ILIKE for the %love% pattern. 
  If nothing is found, I return a row saying NOT FOUND.
*/
CREATE OR REPLACE FUNCTION core.films_in_stock_by_title(pat text)
RETURNS TABLE(id bigint, t text, l text) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        row_number() over ()::bigint,
        f.title::text,
        lan.name::text
    FROM film f
    join language lan on f.language_id = lan.language_id
    WHERE f.title ILIKE pat;

    IF NOT FOUND THEN
        RETURN QUERY SELECT 0::bigint, 'NOT FOUND'::text, 'none'::text;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Task 5. Add new movie
/* I let the database handle the ID (default). 
  I check if the title exists first. 
  If Klingon isn't there, I add it so it doesn't break.
*/
CREATE OR REPLACE FUNCTION core.new_movie(p_t text, p_y int default 2026, p_l text default 'Klingon') 
RETURNS void AS $$
DECLARE
    lid int;
BEGIN
    -- check for same title
    IF EXISTS (select 1 from film where lower(title) = lower(p_t)) THEN
        raise exception 'Movie already exists';
    END IF;

    -- get language id
    select language_id into lid from language where lower(name) = lower(p_l);
    
    if lid is null then
        if lower(p_l) = 'klingon' then
            insert into language (name) values ('Klingon') returning language_id into lid;
        else
            raise exception 'I dont know this language';
        end if;
    end if;

    insert into film (title, release_year, language_id, rental_rate, rental_duration, replacement_cost)
    values (p_t, p_y, lid, 4.99, 3, 19.99);
END;
$$ LANGUAGE plpgsql;
