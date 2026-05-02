-- TASK 2.1 — Create rentaluser with connect-only access
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rentaluser') THEN
        CREATE USER rentaluser WITH PASSWORD 'rentalpassword';
    END IF;
END $$;

GRANT CONNECT ON DATABASE dvdrental TO rentaluser;
GRANT USAGE ON SCHEMA public TO rentaluser;


-- TASK 2.2 — Grant SELECT on customer table to rentaluser

GRANT SELECT ON TABLE public.customer TO rentaluser;

-- Verify: rentaluser can read customer
SET ROLE rentaluser;
SELECT customer_id, first_name, last_name, email FROM public.customer LIMIT 5;
RESET ROLE;

-- Verify: rentaluser cannot read rental (permission denied)
SET ROLE rentaluser;
SELECT rental_id FROM public.rental LIMIT 1;
RESET ROLE;


-- TASK 2.3 — Create group role "rental" and add rentaluser to it

CREATE ROLE rental;
GRANT rental TO rentaluser;


-- TASK 2.4 — Grant INSERT and UPDATE to rental group, test both

GRANT INSERT, UPDATE, SELECT ON TABLE public.rental TO rental;
GRANT USAGE, SELECT ON SEQUENCE public.rental_rental_id_seq TO rental;

-- Insert a new row as rentaluser
SET ROLE rentaluser;
INSERT INTO public.rental (rental_date, inventory_id, customer_id, staff_id, last_update)
VALUES (NOW(), 367, 130, 1, NOW())
RETURNING rental_id;

-- Update the row just inserted
UPDATE public.rental SET return_date = NOW()
WHERE rental_id = (SELECT MAX(rental_id) FROM rental);
RESET ROLE;


-- TASK 2.5 — Revoke INSERT from rental group, verify it is denied

REVOKE INSERT ON TABLE public.rental FROM rental;

-- This should fail with: ERROR: permission denied for table rental
SET ROLE rentaluser;
INSERT INTO public.rental (rental_date, inventory_id, customer_id, staff_id, last_update)
VALUES (NOW(), 368, 131, 1, NOW());
RESET ROLE;


-- TASK 2.6 — Create personalized role for Eleanor Hunt (customer_id = 148)

CREATE ROLE client_eleanor_hunt LOGIN PASSWORD 'eleanor_secure_pass';
GRANT CONNECT ON DATABASE dvdrental TO client_eleanor_hunt;
GRANT USAGE ON SCHEMA public TO client_eleanor_hunt;
GRANT SELECT ON TABLE public.rental, public.payment TO client_eleanor_hunt;


-- TASK 3 — Row-Level Security for client_eleanor_hunt

ALTER TABLE public.rental  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment ENABLE ROW LEVEL SECURITY;

CREATE POLICY rental_customer_policy ON rental
    FOR SELECT TO client_eleanor_hunt
    USING (customer_id = 148);

CREATE POLICY payment_customer_policy ON payment
    FOR SELECT TO client_eleanor_hunt
    USING (customer_id = 148);

-- Verify: Eleanor sees only her 92 rows, all with customer_id = 148
SET ROLE client_eleanor_hunt;
SELECT COUNT(*), MIN(customer_id), MAX(customer_id) FROM rental;
RESET ROLE;

-- Verify: trying to see another customer returns 0 rows
SET ROLE client_eleanor_hunt;
SELECT * FROM public.rental WHERE customer_id = 1;
RESET ROLE;
