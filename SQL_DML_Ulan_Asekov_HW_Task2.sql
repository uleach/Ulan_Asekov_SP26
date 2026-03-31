-- TASK 2: STORAGE INVESTIGATION

-- 1. Setup table
-- Took 6.23s to create 10M rows
CREATE TABLE table_to_delete AS
SELECT 'veeeeeeery_long_string' || x AS col
FROM generate_series(1,(10^7)::int) x;

-- 2. Initial size check
-- Result: 575 MB
SELECT pg_size_pretty(pg_total_relation_size('table_to_delete'));


-- 3. Testing DELETE
-- This took about 10 seconds
DELETE FROM table_to_delete
WHERE REPLACE(col, 'veeeeeeery_long_string','')::int % 3 = 0;

-- 4. Check size again
-- Result: Still 575 MB. 
-- Note: DELETE didn't free space. It just marked rows as "dead" (MVCC).
SELECT pg_size_pretty(pg_total_relation_size('table_to_delete'));


-- 5. Testing VACUUM FULL
-- This rewrites the table to reclaim space
VACUUM FULL VERBOSE table_to_delete;

-- 6. Check size after vacuum
-- Result: 383 MB
SELECT pg_size_pretty(pg_total_relation_size('table_to_delete'));


-- 7. Testing TRUNCATE (Resetting table first)
DROP TABLE IF EXISTS table_to_delete;
CREATE TABLE table_to_delete AS
SELECT 'veeeeeeery_long_string' || x AS col
FROM generate_series(1,(10^7)::int) x;

-- 8. Run TRUNCATE
-- Time: 1.12 seconds
TRUNCATE table_to_delete;

-- 9. Final size check
-- Result: 0 bytes
SELECT pg_size_pretty(pg_total_relation_size('table_to_delete'));


/* SUMMARY OF FINDINGS:
- DELETE is slow (10s) and doesn't shrink the file on disk because of MVCC bloat.
- VACUUM FULL is required to actually get the 575MB down to 383MB.
- TRUNCATE is the fastest (1.12s) and wipes the storage immediately to 0.
*/
