   TASK 1
   ---------------------------------------------------------------------
   Top 5 customers per sales channel by total sales, with a
   sales_percentage KPI showing the customer's share of total sales
   inside their channel.

   How I approached it:
   I needed two things at the same time for every customer — a rank
   inside their channel, and the channel's overall total so I could
   compute the percentage. Doing this with self-joins or subqueries
   would mean scanning the data twice; window functions let me do
   both in one pass.

   Step by step:
     1. First I aggregate raw sales into one row per (channel, customer).
     2. Then I add two window functions side by side:
          - RANK() to get the position inside each channel,
          - SUM() OVER (PARTITION BY channel) to get the channel total.
        I left out ORDER BY in the SUM() on purpose — without ORDER BY
        the function works over the whole partition, which is exactly
        the channel total I need, and there's no implicit window frame.
     3. Finally I keep the top 5 and format the output.

   Why RANK() and not ROW_NUMBER():
   If two customers happen to be tied for 5th place, ROW_NUMBER() would
   silently drop one of them, which feels unfair for a "top 5" report.
   RANK() keeps both, which seems more correct here.
   ===================================================================== */
WITH customer_channel_sales AS (
    -- One row per (channel, customer) with their total spend
    SELECT
        ch.channel_desc,
        c.cust_last_name,
        c.cust_first_name,
        SUM(s.amount_sold) AS total_sales
    FROM sales     s
    JOIN customers c  ON s.cust_id    = c.cust_id
    JOIN channels  ch ON s.channel_id = ch.channel_id
    GROUP BY ch.channel_desc, c.cust_last_name, c.cust_first_name
),
ranked_customers AS (
    -- Rank inside the channel + channel total, both in one scan
    SELECT
        channel_desc,
        cust_last_name,
        cust_first_name,
        total_sales,
        RANK() OVER (PARTITION BY channel_desc
                     ORDER BY total_sales DESC)           AS sales_rank,
        SUM(total_sales) OVER (PARTITION BY channel_desc) AS channel_total
    FROM customer_channel_sales
)
SELECT
    channel_desc,
    cust_last_name,
    cust_first_name,
    -- Money: 2 decimals as required
    TO_CHAR(total_sales, 'FM999999990.00')                            AS amount_sold,
    -- KPI: 4 decimals plus a literal '%' at the end
    TO_CHAR(total_sales / channel_total * 100, 'FM990.0000') || ' %'  AS sales_percentage
FROM ranked_customers
WHERE sales_rank <= 5
ORDER BY channel_desc, total_sales DESC;


/* =====================================================================
   TASK 2
   ---------------------------------------------------------------------
   Total sales of Photo-category products in the Asia region for the
   year 2000, pivoted by quarter, with a YEAR_SUM total column.

   How I approached it:
   The task hint pointed me to the crosstab() function in the tablefunc
   extension, so I used that. The idea is simple — I write a query that
   returns three columns (product, quarter, sum) and crosstab() pivots
   the quarter values into separate columns Q1..Q4.

   A few things that tripped me up while figuring this out:
     - crosstab() needs the inner query to be ordered by row-key, then
       category. If I forgot the ORDER BY, the columns came out wrong.
     - The single-argument form of crosstab() can shift columns when a
       product had no sales in some quarter. I switched to the two-arg
       form with generate_series(1, 4) so the four quarter columns are
       always present, even if a quarter is NULL for a given product.
     - Without COALESCE in the YEAR_SUM expression, NULL + number = NULL,
       so a product missing a single quarter would show no annual total
       at all. COALESCE(..., 0) fixes that.

   Prerequisite (only needs to run once):
       CREATE EXTENSION IF NOT EXISTS tablefunc;
   ===================================================================== */
WITH pivoted AS (
    SELECT *
    FROM crosstab(
        $$
        SELECT
            p.prod_name,
            t.calendar_quarter_number,
            SUM(s.amount_sold)::numeric
        FROM sales s
        JOIN products  p  ON s.prod_id    = p.prod_id
        JOIN times     t  ON s.time_id    = t.time_id
        JOIN customers c  ON s.cust_id    = c.cust_id
        JOIN countries co ON c.country_id = co.country_id
        WHERE p.prod_category   = 'Photo'
          AND co.country_region = 'Asia'
          AND t.calendar_year   = 2000
        GROUP BY p.prod_name, t.calendar_quarter_number
        ORDER BY 1, 2          -- crosstab needs this ordering
        $$,
        $$ SELECT generate_series(1, 4) $$  -- forces Q1..Q4 columns
    ) AS ct (
        prod_name VARCHAR,
        q1 NUMERIC,
        q2 NUMERIC,
        q3 NUMERIC,
        q4 NUMERIC
    )
)
SELECT
    prod_name,
    TO_CHAR(q1, 'FM999999990.00') AS q1,
    TO_CHAR(q2, 'FM999999990.00') AS q2,
    TO_CHAR(q3, 'FM999999990.00') AS q3,
    TO_CHAR(q4, 'FM999999990.00') AS q4,
    TO_CHAR(
        COALESCE(q1,0) + COALESCE(q2,0) + COALESCE(q3,0) + COALESCE(q4,0),
        'FM999999990.00'
    ) AS year_sum
FROM pivoted
ORDER BY COALESCE(q1,0) + COALESCE(q2,0) + COALESCE(q3,0) + COALESCE(q4,0) DESC;


/* =====================================================================
   TASK 3
   ---------------------------------------------------------------------
   Sales report for the top 300 customers by combined sales across
   1998, 1999 and 2001, grouped by sales channel.

   How I read the task:
   "Top 300 customers based on total sales in the years 1998, 1999 and
   2001" — I understood this as one combined ranking: sum each
   customer's sales over those three years and take the top 300 from
   that single list. (My first attempt was an intersection — top 300
   in each year separately — but that returned almost no rows, which
   makes sense because the same 300 people don't lead every year.
   The combined-total reading matches the sample output much better.)

   Step by step:
     1. customer_3yr_totals: one row per customer with their total spend
        across the three target years.
     2. top_300: rank that list with RANK() and keep rank <= 300.
        I used RANK() instead of ROW_NUMBER() so that ties at the cutoff
        are not arbitrarily dropped.
     3. Final SELECT: for those qualifying customers, sum their sales
        per channel within the same 3-year window. The task says
        "include only purchases made on the channel specified", which
        I read as: each row's amount_sold is what that customer spent
        through that one channel (so a customer can appear under
        multiple channels, like in the sample with Kane / Meredith).

   No window frames are used — only PARTITION BY / ORDER BY clauses.
   ===================================================================== */
WITH customer_3yr_totals AS (
    -- Step 1: one row per customer, total over the 3 years
    SELECT
        s.cust_id,
        SUM(s.amount_sold) AS total_3yr
    FROM sales s
    JOIN times t ON s.time_id = t.time_id
    WHERE t.calendar_year IN (1998, 1999, 2001)
    GROUP BY s.cust_id
),
top_300 AS (
    -- Step 2: rank by combined total, keep top 300
    SELECT cust_id, total_3yr
    FROM (
        SELECT
            cust_id,
            total_3yr,
            RANK() OVER (ORDER BY total_3yr DESC) AS overall_rank
        FROM customer_3yr_totals
    ) ranked
    WHERE overall_rank <= 300
)
-- Step 3: per-channel report for those customers, same time window
SELECT
    ch.channel_desc,
    c.cust_id,
    c.cust_last_name,
    c.cust_first_name,
    TO_CHAR(SUM(s.amount_sold), 'FM999999990.00') AS amount_sold
FROM sales s
JOIN customers c  ON s.cust_id    = c.cust_id
JOIN channels  ch ON s.channel_id = ch.channel_id
JOIN times     t  ON s.time_id    = t.time_id
WHERE s.cust_id IN (SELECT cust_id FROM top_300)
  AND t.calendar_year IN (1998, 1999, 2001)
GROUP BY ch.channel_desc, c.cust_id, c.cust_last_name, c.cust_first_name
ORDER BY ch.channel_desc, SUM(s.amount_sold) DESC;


/* =====================================================================
   TASK 4
   ---------------------------------------------------------------------
   Sales report for January, February and March 2000, for the Europe
   and Americas regions, by month and product category in alphabetical
   order.

   How I approached it:
   This is another pivot, but smaller — only two regions become columns,
   so I didn't think it was worth pulling in crosstab() again. Instead
   I used SUM() ... FILTER (WHERE region = ...), which feels cleaner:
   each conditional sum becomes its own column directly inside SELECT.

   I also pushed the month and region filters into WHERE rather than
   leaving the FILTER clauses to do all the work. The reason is that
   WHERE limits the rows that ever enter the aggregation, so the query
   does less work.

   Notes on formatting:
     - 'FM999G999G990D00' uses locale-aware separators. G = thousands,
       D = decimal point, FM strips padding spaces. If the database
       locale changed the separators, I would switch to the explicit
       'FM999,999,990.00' to force commas.
     - The aliases "Americas SALES" and "Europe SALES" are double-quoted
       to keep the space and capitalization shown in the sample.
   ===================================================================== */
SELECT
    t.calendar_month_desc,
    p.prod_category,
    TO_CHAR(
        SUM(s.amount_sold) FILTER (WHERE co.country_region = 'Americas'),
        'FM999G999G990D00'
    ) AS "Americas SALES",
    TO_CHAR(
        SUM(s.amount_sold) FILTER (WHERE co.country_region = 'Europe'),
        'FM999G999G990D00'
    ) AS "Europe SALES"
FROM sales s
JOIN products  p  ON s.prod_id    = p.prod_id
JOIN times     t  ON s.time_id    = t.time_id
JOIN customers c  ON s.cust_id    = c.cust_id
JOIN countries co ON c.country_id = co.country_id
WHERE t.calendar_month_desc IN ('2000-01', '2000-02', '2000-03')
  AND co.country_region     IN ('Americas', 'Europe')
GROUP BY t.calendar_month_desc, p.prod_category
ORDER BY t.calendar_month_desc, p.prod_category;
