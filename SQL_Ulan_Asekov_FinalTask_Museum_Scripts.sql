-- This script builds a full Museum database in PostgreSQL:
--   1) Creates a separate database (museum_db) and schema (museum)
--   2) Creates 8 tables in 3NF with PKs, FKs, and 5+ CHECK constraints
--   3) Populates each table with 6+ rows for the last 3 months
--   4) Creates two functions (generic update + add ticket sale)
--   5) Creates an analytics view for the most recent quarter
--   6) Creates a read-only manager role
-- The script is rerunnable: it drops and recreates all objects safely.
-- All surrogate keys are SERIAL; DML statements never insert them manually.

-- STEP 1: Create database and schema

-- DROP DATABASE IF EXISTS museum_db;
-- CREATE DATABASE museum_db;
-- \c museum_db

DROP SCHEMA IF EXISTS museum CASCADE;
CREATE SCHEMA museum;

-- Make all subsequent objects use this schema by default
SET search_path TO museum;

-- STEP 2: Create tables (parents first, children after)

-- ---------- department ----------
-- Top-level organisational unit. Other tables reference it.
CREATE TABLE department (
    department_id SERIAL       PRIMARY KEY,
    name          VARCHAR(100) NOT NULL,
    description   TEXT,
    created_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ---------- storage_location ----------
-- Physical rooms where artifacts are stored. No FK dependencies.
CREATE TABLE storage_location (
    storage_location_id SERIAL        PRIMARY KEY,
    room_code           VARCHAR(20)   NOT NULL,
    floor               SMALLINT      NOT NULL,
    -- temperature and humidity stored as numeric so we can validate ranges
    temperature_c       NUMERIC(4,1),
    humidity_pct        NUMERIC(4,1),
    capacity            INT
);

-- ---------- employee ----------
-- Staff. References department.
-- full_name is GENERATED ALWAYS AS so it stays consistent with first/last name.
CREATE TABLE employee (
    employee_id    SERIAL       PRIMARY KEY,
    department_id  INT          NOT NULL REFERENCES department(department_id),
    first_name     VARCHAR(50)  NOT NULL,
    last_name      VARCHAR(50)  NOT NULL,
    email          VARCHAR(100) NOT NULL,
    hire_date      DATE         NOT NULL,
    full_name      TEXT GENERATED ALWAYS AS (first_name || ' ' || last_name) STORED,
    is_active      BOOLEAN      NOT NULL DEFAULT TRUE
);

-- ---------- artifact ----------
-- The actual museum collection items. References department and storage_location.
CREATE TABLE artifact (
    artifact_id          SERIAL        PRIMARY KEY,
    department_id        INT           NOT NULL REFERENCES department(department_id),
    storage_location_id  INT           NOT NULL REFERENCES storage_location(storage_location_id),
    title                VARCHAR(150)  NOT NULL,
    origin_country       VARCHAR(60),
    estimated_year       SMALLINT,         -- can be negative for BC dates
    valuation_usd        NUMERIC(12,2),
    condition            VARCHAR(20),      -- excellent / good / fair / poor
    acquired_at          DATE          NOT NULL DEFAULT CURRENT_DATE
);

-- ---------- exhibition ----------
-- Planned exhibitions. References employee (the curator).
CREATE TABLE exhibition (
    exhibition_id        SERIAL        PRIMARY KEY,
    curator_employee_id  INT           NOT NULL REFERENCES employee(employee_id),
    title                VARCHAR(150)  NOT NULL,
    start_date           DATE          NOT NULL,
    end_date             DATE          NOT NULL,
    ticket_price_usd     NUMERIC(6,2)  NOT NULL,
    is_free              BOOLEAN       NOT NULL DEFAULT FALSE,
    is_active            BOOLEAN       NOT NULL DEFAULT TRUE
);

-- ---------- exhibition_artifact ----------
-- Junction table for the M:N relationship between exhibition and artifact.
-- A single artifact can appear in multiple exhibitions over time, and
-- an exhibition has many artifacts.
CREATE TABLE exhibition_artifact (
    exhibition_id  INT       NOT NULL REFERENCES exhibition(exhibition_id) ON DELETE CASCADE,
    artifact_id    INT       NOT NULL REFERENCES artifact(artifact_id),
    display_order  SMALLINT,
    added_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (exhibition_id, artifact_id)
);

-- ---------- visitor ----------
-- People who buy tickets. No FK dependencies.
CREATE TABLE visitor (
    visitor_id     SERIAL        PRIMARY KEY,
    first_name     VARCHAR(50)   NOT NULL,
    last_name      VARCHAR(50)   NOT NULL,
    email          VARCHAR(100),
    country        VARCHAR(60),
    registered_at  TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ---------- ticket_sale ----------
-- The transaction table. References visitor, exhibition, and the employee
-- who sold the ticket. total_price_usd is a STORED generated column so
-- the database always keeps it consistent with quantity * unit_price_usd.
CREATE TABLE ticket_sale (
    ticket_sale_id        SERIAL        PRIMARY KEY,
    visitor_id            INT           NOT NULL REFERENCES visitor(visitor_id),
    exhibition_id         INT           NOT NULL REFERENCES exhibition(exhibition_id),
    sold_by_employee_id   INT           NOT NULL REFERENCES employee(employee_id),
    sale_datetime         TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    quantity              SMALLINT      NOT NULL DEFAULT 1,
    unit_price_usd        NUMERIC(6,2)  NOT NULL,
    total_price_usd       NUMERIC(8,2)  GENERATED ALWAYS AS (quantity * unit_price_usd) STORED,
    payment_method        VARCHAR(20)   NOT NULL DEFAULT 'card'
);

-- STEP 3: Add CHECK constraints (5+ named constraints across tables)

-- 1) Acquired date must be in the past or today (no future acquisitions)
ALTER TABLE artifact
    ADD CONSTRAINT chk_artifact_acquired_at_not_future
    CHECK (acquired_at <= CURRENT_DATE);

-- 2) Artifact valuation cannot be negative
ALTER TABLE artifact
    ADD CONSTRAINT chk_artifact_valuation_nonneg
    CHECK (valuation_usd IS NULL OR valuation_usd >= 0);

-- 3) Condition can only be one of a fixed set of values
ALTER TABLE artifact
    ADD CONSTRAINT chk_artifact_condition_allowed
    CHECK (condition IS NULL OR condition IN ('excellent', 'good', 'fair', 'poor'));

-- 4) Exhibition end_date must be on or after start_date
ALTER TABLE exhibition
    ADD CONSTRAINT chk_exhibition_dates_valid
    CHECK (end_date >= start_date);

-- 5) Ticket price must be non-negative AND consistent with is_free flag
ALTER TABLE exhibition
    ADD CONSTRAINT chk_exhibition_ticket_price_nonneg
    CHECK (ticket_price_usd >= 0);

ALTER TABLE exhibition
    ADD CONSTRAINT chk_exhibition_free_price_consistent
    CHECK (
        (is_free = TRUE  AND ticket_price_usd = 0)
        OR
        (is_free = FALSE AND ticket_price_usd > 0)
    );

-- 6) Visitor email must be unique when provided (UNIQUE constraint counts as a constraint)
ALTER TABLE visitor
    ADD CONSTRAINT uq_visitor_email
    UNIQUE (email);

-- 7) Ticket sale quantity must be 1 or more
ALTER TABLE ticket_sale
    ADD CONSTRAINT chk_ticket_sale_quantity_positive
    CHECK (quantity >= 1);

-- 8) Payment method limited to allowed values
ALTER TABLE ticket_sale
    ADD CONSTRAINT chk_ticket_sale_payment_method
    CHECK (payment_method IN ('card', 'cash', 'online'));

-- 9) Storage temperature/humidity must be in sensible ranges if provided
ALTER TABLE storage_location
    ADD CONSTRAINT chk_storage_temperature_range
    CHECK (temperature_c IS NULL OR temperature_c BETWEEN -10 AND 50);

ALTER TABLE storage_location
    ADD CONSTRAINT chk_storage_humidity_range
    CHECK (humidity_pct IS NULL OR humidity_pct BETWEEN 0 AND 100);

-- STEP 4: Populate tables with sample data (last 3 months, 6+ rows each)
-- Surrogate IDs are NOT specified anywhere — SERIAL handles them.
-- Most rows use date references like CURRENT_DATE - INTERVAL '20 days' so
-- the data remains "in the last 3 months" no matter when the script runs.

-- ---------- department ----------
INSERT INTO department (name, description) VALUES
('Egyptology',                'Ancient Egyptian collection — pharaonic artifacts, mummies, papyri.'),
('Modern Art',                'Paintings and sculpture from 1900 onwards.'),
('Asian Art',                 'Chinese, Japanese, and Korean collections.'),
('Natural History',           'Fossils, taxidermy, mineral specimens.'),
('Medieval European',         'Manuscripts, weapons, religious artifacts from 500-1500 CE.'),
('Photography',               'Historic and contemporary photographic prints.'),
('Kyrgyz & Central Asian Art','Traditional Kyrgyz, Kazakh, and Uzbek artifacts including textiles, jewellery, yurts, and Silk Road items.');

-- ---------- storage_location ----------
INSERT INTO storage_location (room_code, floor, temperature_c, humidity_pct, capacity) VALUES
('B1-EGY-01', -1, 19.5, 45.0, 200),
('B1-MOD-02', -1, 21.0, 50.0, 150),
('B1-ASN-03', -1, 20.0, 48.0, 180),
('G-NAT-04',   0, 22.0, 55.0, 250),
('G-MED-05',   0, 18.5, 42.0, 120),
('1-PHO-06',   1, 16.0, 35.0,  80),
('1-CAS-07',   1, 19.0, 45.0, 160);

-- ---------- employee ----------
-- Each employee uses department name lookup (not hardcoded IDs)
INSERT INTO employee (department_id, first_name, last_name, email, hire_date, is_active) VALUES
((SELECT department_id FROM department WHERE name='Egyptology'),                'Amelia',  'Brooks',     'amelia.brooks@museum.org',     CURRENT_DATE - INTERVAL '4 years', TRUE),
((SELECT department_id FROM department WHERE name='Modern Art'),                'Aizada',  'Beksultan',  'aizada.beksultan@museum.org',  CURRENT_DATE - INTERVAL '2 years', TRUE),
((SELECT department_id FROM department WHERE name='Asian Art'),                 'Yuki',    'Tanaka',     'yuki.tanaka@museum.org',       CURRENT_DATE - INTERVAL '3 years', TRUE),
((SELECT department_id FROM department WHERE name='Natural History'),           'Bakyt',   'Toktogulov', 'bakyt.toktogulov@museum.org',  CURRENT_DATE - INTERVAL '5 years', TRUE),
((SELECT department_id FROM department WHERE name='Medieval European'),         'Sofia',   'Rossi',      'sofia.rossi@museum.org',       CURRENT_DATE - INTERVAL '1 year',  TRUE),
((SELECT department_id FROM department WHERE name='Photography'),               'Aibek',   'Sadyrbaev',  'aibek.sadyrbaev@museum.org',   CURRENT_DATE - INTERVAL '6 months',TRUE),
((SELECT department_id FROM department WHERE name='Kyrgyz & Central Asian Art'),'Cholpon', 'Asanova',    'cholpon.asanova@museum.org',   CURRENT_DATE - INTERVAL '3 years', TRUE);

-- ---------- artifact ----------
INSERT INTO artifact (department_id, storage_location_id, title, origin_country, estimated_year, valuation_usd, condition, acquired_at) VALUES
((SELECT department_id FROM department WHERE name='Egyptology'),
 (SELECT storage_location_id FROM storage_location WHERE room_code='B1-EGY-01'),
 'Funerary Mask of Amenhotep', 'Egypt', -1350, 850000.00, 'excellent', CURRENT_DATE - INTERVAL '80 days'),

((SELECT department_id FROM department WHERE name='Modern Art'),
 (SELECT storage_location_id FROM storage_location WHERE room_code='B1-MOD-02'),
 'Untitled No. 7 (1962)', 'United States', 1962, 4500000.00, 'good', CURRENT_DATE - INTERVAL '60 days'),

((SELECT department_id FROM department WHERE name='Asian Art'),
 (SELECT storage_location_id FROM storage_location WHERE room_code='B1-ASN-03'),
 'Ming Dynasty Vase',  'China',  1450,  320000.00, 'good',      CURRENT_DATE - INTERVAL '45 days'),

((SELECT department_id FROM department WHERE name='Natural History'),
 (SELECT storage_location_id FROM storage_location WHERE room_code='G-NAT-04'),
 'Triceratops Fossil', 'United States', NULL, 1200000.00, 'fair', CURRENT_DATE - INTERVAL '30 days'),

((SELECT department_id FROM department WHERE name='Medieval European'),
 (SELECT storage_location_id FROM storage_location WHERE room_code='G-MED-05'),
 'Illuminated Book of Hours', 'France',     1380, 180000.00, 'excellent', CURRENT_DATE - INTERVAL '20 days'),

((SELECT department_id FROM department WHERE name='Photography'),
 (SELECT storage_location_id FROM storage_location WHERE room_code='1-PHO-06'),
 'Dust Bowl Portrait (1936)', 'United States', 1936,  45000.00, 'good',      CURRENT_DATE - INTERVAL '10 days'),

((SELECT department_id FROM department WHERE name='Kyrgyz & Central Asian Art'),
 (SELECT storage_location_id FROM storage_location WHERE room_code='1-CAS-07'),
 'Shyrdak Felt Carpet (Issyk-Kul)', 'Kyrgyzstan', 1920, 28000.00, 'excellent', CURRENT_DATE - INTERVAL '70 days'),

((SELECT department_id FROM department WHERE name='Kyrgyz & Central Asian Art'),
 (SELECT storage_location_id FROM storage_location WHERE room_code='1-CAS-07'),
 'Silver Saukele Headdress', 'Kazakhstan', 1880, 95000.00, 'good',      CURRENT_DATE - INTERVAL '55 days'),

((SELECT department_id FROM department WHERE name='Kyrgyz & Central Asian Art'),
 (SELECT storage_location_id FROM storage_location WHERE room_code='1-CAS-07'),
 'Komuz (Traditional Three-Stringed Lute)', 'Kyrgyzstan', 1955, 12000.00, 'good', CURRENT_DATE - INTERVAL '25 days');

-- ---------- exhibition ----------
INSERT INTO exhibition (curator_employee_id, title, start_date, end_date, ticket_price_usd, is_free, is_active) VALUES
((SELECT employee_id FROM employee WHERE email='amelia.brooks@museum.org'),
 'Treasures of Ancient Egypt', CURRENT_DATE - INTERVAL '70 days', CURRENT_DATE + INTERVAL '20 days', 25.00, FALSE, TRUE),

((SELECT employee_id FROM employee WHERE email='aizada.beksultan@museum.org'),
 'Abstract Expressionism: A Retrospective', CURRENT_DATE - INTERVAL '50 days', CURRENT_DATE + INTERVAL '40 days', 22.00, FALSE, TRUE),

((SELECT employee_id FROM employee WHERE email='yuki.tanaka@museum.org'),
 'Imperial China: Ceramics & Silk', CURRENT_DATE - INTERVAL '40 days', CURRENT_DATE + INTERVAL '30 days', 20.00, FALSE, TRUE),

((SELECT employee_id FROM employee WHERE email='bakyt.toktogulov@museum.org'),
 'Dinosaurs Among Us',         CURRENT_DATE - INTERVAL '25 days', CURRENT_DATE + INTERVAL '60 days', 18.00, FALSE, TRUE),

((SELECT employee_id FROM employee WHERE email='sofia.rossi@museum.org'),
 'Manuscripts of the Middle Ages', CURRENT_DATE - INTERVAL '15 days', CURRENT_DATE + INTERVAL '45 days', 16.00, FALSE, TRUE),

((SELECT employee_id FROM employee WHERE email='aibek.sadyrbaev@museum.org'),
 'America in Black and White',  CURRENT_DATE - INTERVAL '5 days',  CURRENT_DATE + INTERVAL '55 days', 15.00, FALSE, TRUE),

((SELECT employee_id FROM employee WHERE email='cholpon.asanova@museum.org'),
 'Silk Road Heritage: Kyrgyz & Central Asian Treasures', CURRENT_DATE - INTERVAL '35 days', CURRENT_DATE + INTERVAL '50 days', 18.00, FALSE, TRUE),

((SELECT employee_id FROM employee WHERE email='cholpon.asanova@museum.org'),
 'Nooruz Family Day: Free Children''s Exhibition', CURRENT_DATE - INTERVAL '10 days', CURRENT_DATE + INTERVAL '5 days', 0.00, TRUE, TRUE);

-- ---------- exhibition_artifact (M:N junction) ----------
INSERT INTO exhibition_artifact (exhibition_id, artifact_id, display_order) VALUES
((SELECT exhibition_id FROM exhibition WHERE title='Treasures of Ancient Egypt'),
 (SELECT artifact_id   FROM artifact   WHERE title='Funerary Mask of Amenhotep'), 1),

((SELECT exhibition_id FROM exhibition WHERE title='Abstract Expressionism: A Retrospective'),
 (SELECT artifact_id   FROM artifact   WHERE title='Untitled No. 7 (1962)'), 1),

((SELECT exhibition_id FROM exhibition WHERE title='Imperial China: Ceramics & Silk'),
 (SELECT artifact_id   FROM artifact   WHERE title='Ming Dynasty Vase'), 1),

((SELECT exhibition_id FROM exhibition WHERE title='Dinosaurs Among Us'),
 (SELECT artifact_id   FROM artifact   WHERE title='Triceratops Fossil'), 1),

((SELECT exhibition_id FROM exhibition WHERE title='Manuscripts of the Middle Ages'),
 (SELECT artifact_id   FROM artifact   WHERE title='Illuminated Book of Hours'), 1),

((SELECT exhibition_id FROM exhibition WHERE title='America in Black and White'),
 (SELECT artifact_id   FROM artifact   WHERE title='Dust Bowl Portrait (1936)'), 1),

((SELECT exhibition_id FROM exhibition WHERE title='Silk Road Heritage: Kyrgyz & Central Asian Treasures'),
 (SELECT artifact_id   FROM artifact   WHERE title='Shyrdak Felt Carpet (Issyk-Kul)'), 1),

((SELECT exhibition_id FROM exhibition WHERE title='Silk Road Heritage: Kyrgyz & Central Asian Treasures'),
 (SELECT artifact_id   FROM artifact   WHERE title='Silver Saukele Headdress'), 2),

((SELECT exhibition_id FROM exhibition WHERE title='Silk Road Heritage: Kyrgyz & Central Asian Treasures'),
 (SELECT artifact_id   FROM artifact   WHERE title='Komuz (Traditional Three-Stringed Lute)'), 3),

((SELECT exhibition_id FROM exhibition WHERE title='Nooruz Family Day: Free Children''s Exhibition'),
 (SELECT artifact_id   FROM artifact   WHERE title='Komuz (Traditional Three-Stringed Lute)'), 1),

((SELECT exhibition_id FROM exhibition WHERE title='Manuscripts of the Middle Ages'),
 (SELECT artifact_id   FROM artifact   WHERE title='Funerary Mask of Amenhotep'), 2);

-- ---------- visitor ----------
INSERT INTO visitor (first_name, last_name, email, country) VALUES
('Maria',   'Lopez',          'maria.lopez@example.com',          'Spain'),
('Aizat',   'Bakir uulu',     'aizat.bakiruulu@example.com',      'Kyrgyzstan'),
('Aisha',   'Khan',           'aisha.khan@example.com',           'United Kingdom'),
('Begimai', 'Toktorbek kyzy', 'begimai.toktorbekkyzy@example.com','Kyrgyzstan'),
('Hans',    'Mueller',        'hans.mueller@example.com',         'Germany'),
('Emir',    'Joldoshev',      'emir.joldoshev@example.com',       'Kyrgyzstan'),
('Aizada',  'Sultanova',      'aizada.sultanova@example.com',     'Kyrgyzstan'),
('Nurlan',  'Asan uulu',      'nurlan.asanuulu@example.com',      'Kyrgyzstan');

-- ---------- ticket_sale (transactions in last 3 months) ----------
INSERT INTO ticket_sale (visitor_id, exhibition_id, sold_by_employee_id, sale_datetime, quantity, unit_price_usd, payment_method) VALUES
((SELECT visitor_id FROM visitor WHERE email='maria.lopez@example.com'),
 (SELECT exhibition_id FROM exhibition WHERE title='Treasures of Ancient Egypt'),
 (SELECT employee_id FROM employee WHERE email='amelia.brooks@museum.org'),
 CURRENT_TIMESTAMP - INTERVAL '60 days', 2, 25.00, 'card'),

((SELECT visitor_id FROM visitor WHERE email='aizat.bakiruulu@example.com'),
 (SELECT exhibition_id FROM exhibition WHERE title='Abstract Expressionism: A Retrospective'),
 (SELECT employee_id FROM employee WHERE email='aizada.beksultan@museum.org'),
 CURRENT_TIMESTAMP - INTERVAL '45 days', 1, 22.00, 'cash'),

((SELECT visitor_id FROM visitor WHERE email='aisha.khan@example.com'),
 (SELECT exhibition_id FROM exhibition WHERE title='Imperial China: Ceramics & Silk'),
 (SELECT employee_id FROM employee WHERE email='yuki.tanaka@museum.org'),
 CURRENT_TIMESTAMP - INTERVAL '30 days', 4, 20.00, 'online'),

((SELECT visitor_id FROM visitor WHERE email='begimai.toktorbekkyzy@example.com'),
 (SELECT exhibition_id FROM exhibition WHERE title='Dinosaurs Among Us'),
 (SELECT employee_id FROM employee WHERE email='bakyt.toktogulov@museum.org'),
 CURRENT_TIMESTAMP - INTERVAL '20 days', 3, 18.00, 'card'),

((SELECT visitor_id FROM visitor WHERE email='hans.mueller@example.com'),
 (SELECT exhibition_id FROM exhibition WHERE title='Manuscripts of the Middle Ages'),
 (SELECT employee_id FROM employee WHERE email='sofia.rossi@museum.org'),
 CURRENT_TIMESTAMP - INTERVAL '12 days', 2, 16.00, 'card'),

((SELECT visitor_id FROM visitor WHERE email='emir.joldoshev@example.com'),
 (SELECT exhibition_id FROM exhibition WHERE title='America in Black and White'),
 (SELECT employee_id FROM employee WHERE email='aibek.sadyrbaev@museum.org'),
 CURRENT_TIMESTAMP - INTERVAL '4 days', 1, 15.00, 'online'),

((SELECT visitor_id FROM visitor WHERE email='aizada.sultanova@example.com'),
 (SELECT exhibition_id FROM exhibition WHERE title='Silk Road Heritage: Kyrgyz & Central Asian Treasures'),
 (SELECT employee_id FROM employee WHERE email='cholpon.asanova@museum.org'),
 CURRENT_TIMESTAMP - INTERVAL '15 days', 3, 18.00, 'card'),

((SELECT visitor_id FROM visitor WHERE email='nurlan.asanuulu@example.com'),
 (SELECT exhibition_id FROM exhibition WHERE title='Silk Road Heritage: Kyrgyz & Central Asian Treasures'),
 (SELECT employee_id FROM employee WHERE email='cholpon.asanova@museum.org'),
 CURRENT_TIMESTAMP - INTERVAL '8 days', 2, 18.00, 'online'),

((SELECT visitor_id FROM visitor WHERE email='begimai.toktorbekkyzy@example.com'),
 (SELECT exhibition_id FROM exhibition WHERE title='Nooruz Family Day: Free Children''s Exhibition'),
 (SELECT employee_id FROM employee WHERE email='cholpon.asanova@museum.org'),
 CURRENT_TIMESTAMP - INTERVAL '6 days', 4, 0.00, 'cash');

-- STEP 5: Functions

-- ---------- 5.1: Generic update function ----------
-- Updates one column of one row in any of our tables. Takes:
--   - table name
--   - primary key column name
--   - primary key value
--   - column to update
--   - new value (as TEXT — caller is responsible for sensible values)
-- Uses dynamic SQL (EXECUTE) because the table and column names are
-- parameters and cannot be referenced statically.

CREATE OR REPLACE FUNCTION museum.update_table_column(
    p_table_name  TEXT,
    p_pk_column   TEXT,
    p_pk_value    INT,
    p_column_name TEXT,
    p_new_value   TEXT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_sql TEXT;
BEGIN
    -- Validate the table exists in the museum schema
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'museum' AND table_name = p_table_name
    ) THEN
        RAISE EXCEPTION 'Table museum.% does not exist.', p_table_name;
    END IF;

    -- Validate the column exists
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'museum'
          AND table_name = p_table_name
          AND column_name = p_column_name
    ) THEN
        RAISE EXCEPTION 'Column %.% does not exist.', p_table_name, p_column_name;
    END IF;

    -- Build and run the UPDATE. quote_ident protects against injection in
    -- the identifier parts; the value is parameterised via USING.
    v_sql := format(
        'UPDATE museum.%I SET %I = $1 WHERE %I = $2',
        p_table_name, p_column_name, p_pk_column
    );
    EXECUTE v_sql USING p_new_value, p_pk_value;

    RAISE NOTICE 'Updated %.% = % where % = %',
        p_table_name, p_column_name, p_new_value, p_pk_column, p_pk_value;
END;
$$;

-- Test:
-- SELECT museum.update_table_column('visitor', 'visitor_id', 1, 'country', 'France');
-- SELECT * FROM museum.visitor WHERE visitor_id = 1;


-- ---------- 5.2: Add ticket_sale (transaction) function ----------
-- Inserts a new ticket_sale row using natural keys (emails, titles) so the
-- caller never needs to look up surrogate IDs.

CREATE OR REPLACE FUNCTION museum.add_ticket_sale(
    p_visitor_email     TEXT,
    p_exhibition_title  TEXT,
    p_employee_email    TEXT,
    p_quantity          SMALLINT DEFAULT 1,
    p_payment_method    TEXT     DEFAULT 'card'
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_visitor_id    INT;
    v_exhibition_id INT;
    v_employee_id   INT;
    v_unit_price    NUMERIC(6,2);
    v_new_id        INT;
BEGIN
    -- Look up visitor by email
    SELECT visitor_id INTO v_visitor_id
    FROM museum.visitor WHERE email = p_visitor_email;
    IF v_visitor_id IS NULL THEN
        RAISE EXCEPTION 'Visitor with email % not found.', p_visitor_email;
    END IF;

    -- Look up exhibition by title (and grab its current ticket price)
    SELECT exhibition_id, ticket_price_usd
    INTO   v_exhibition_id, v_unit_price
    FROM   museum.exhibition WHERE title = p_exhibition_title;
    IF v_exhibition_id IS NULL THEN
        RAISE EXCEPTION 'Exhibition % not found.', p_exhibition_title;
    END IF;

    -- Look up employee by email
    SELECT employee_id INTO v_employee_id
    FROM museum.employee WHERE email = p_employee_email;
    IF v_employee_id IS NULL THEN
        RAISE EXCEPTION 'Employee with email % not found.', p_employee_email;
    END IF;

    -- Insert the sale - ticket_sale_id and total_price_usd are auto-generated
    INSERT INTO museum.ticket_sale (
        visitor_id, exhibition_id, sold_by_employee_id,
        quantity, unit_price_usd, payment_method
    )
    VALUES (
        v_visitor_id, v_exhibition_id, v_employee_id,
        p_quantity, v_unit_price, p_payment_method
    )
    RETURNING ticket_sale_id INTO v_new_id;

    RAISE NOTICE 'Ticket sale % created (% × %): $%',
        v_new_id, p_quantity, p_exhibition_title, p_quantity * v_unit_price;
    RETURN v_new_id;
END;
$$;

-- Test:
-- SELECT museum.add_ticket_sale(
--     'maria.lopez@example.com',
--     'Dinosaurs Among Us',
--     bakyt.toktogulov@museum.org,
--     2::SMALLINT,
--     'card'
-- );


-- STEP 6: Analytics view for the most recent quarter
-- Shows aggregated ticket sales for the most recently active quarter
-- (whichever quarter contains the latest sale_datetime in the database).
-- Excludes surrogate keys to keep the result clean for analysis.

CREATE OR REPLACE VIEW museum.v_recent_quarter_sales AS
WITH latest AS (
    SELECT
        EXTRACT(QUARTER FROM MAX(sale_datetime))::INT AS q,
        EXTRACT(YEAR    FROM MAX(sale_datetime))::INT AS y
    FROM museum.ticket_sale
)
SELECT
    e.title                              AS exhibition_title,
    COUNT(DISTINCT ts.ticket_sale_id)    AS sales_count,
    SUM(ts.quantity)                     AS tickets_sold,
    SUM(ts.total_price_usd)              AS total_revenue_usd,
    ROUND(AVG(ts.total_price_usd), 2)    AS average_sale_value,
    MIN(ts.sale_datetime)::DATE          AS first_sale_date,
    MAX(ts.sale_datetime)::DATE          AS last_sale_date
FROM museum.ticket_sale ts
JOIN museum.exhibition  e ON ts.exhibition_id = e.exhibition_id
CROSS JOIN latest l
WHERE EXTRACT(QUARTER FROM ts.sale_datetime) = l.q
  AND EXTRACT(YEAR    FROM ts.sale_datetime) = l.y
GROUP BY e.title
ORDER BY total_revenue_usd DESC;

-- Test:
-- SELECT * FROM museum.v_recent_quarter_sales;

-- STEP 7: Read-only manager role
-- Best practice: separate roles for separate purposes. The manager only
-- needs SELECT access to read reports — they do not need INSERT/UPDATE/DELETE.
-- DROP first so this script is rerunnable. Use DO block to handle the case
-- where the role doesn't exist yet on first run.

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'museum_manager') THEN
        REVOKE ALL ON ALL TABLES IN SCHEMA museum FROM museum_manager;
        REVOKE ALL ON SCHEMA museum FROM museum_manager;
        REVOKE ALL ON DATABASE museum_db FROM museum_manager;
        DROP ROLE museum_manager;
    END IF;
END $$;

CREATE ROLE museum_manager WITH
    LOGIN
    PASSWORD 'manager_password'
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    CONNECTION LIMIT 5;          -- limit concurrent connections for safety

GRANT CONNECT ON DATABASE museum_db TO museum_manager;
GRANT USAGE ON SCHEMA museum TO museum_manager;

-- Read-only access to all tables
GRANT SELECT ON ALL TABLES IN SCHEMA museum TO museum_manager;

-- Also grant SELECT on any tables created in the future
ALTER DEFAULT PRIVILEGES IN SCHEMA museum
    GRANT SELECT ON TABLES TO museum_manager;

-- Verify the role:
-- SELECT rolname, rolcanlogin, rolconnlimit FROM pg_roles WHERE rolname = 'museum_manager';
