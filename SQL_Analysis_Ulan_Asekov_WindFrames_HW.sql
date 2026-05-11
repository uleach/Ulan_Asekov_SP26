-- TASK 1 — Annual sales by channel and region, 1999-2001
-- For each region/year/channel I need:
--   - total amount sold
--   - that channel's % share of the year's regional total
--   - the same % from the previous year
--   - the difference between them

-- Step 1: get the totals grouped by region, year, channel
WITH sales_by_channel AS (
    SELECT
        co.country_region,
        t.calendar_year,
        ch.channel_desc,
        SUM(s.amount_sold) AS amount_sold
    FROM sales s
    JOIN times t      ON s.time_id = t.time_id
    JOIN channels ch  ON s.channel_id = ch.channel_id
    JOIN customers cu ON s.cust_id = cu.cust_id
    JOIN countries co ON cu.country_id = co.country_id
    WHERE t.calendar_year IN (1999, 2000, 2001)
      AND co.country_region IN ('Americas', 'Asia', 'Europe')
    GROUP BY co.country_region, t.calendar_year, ch.channel_desc
),
-- Step 2: calculate the % share per region/year using a window
sales_with_pct AS (
    SELECT
        country_region,
        calendar_year,
        channel_desc,
        amount_sold,
        ROUND(
            amount_sold * 100.0
            / SUM(amount_sold) OVER (PARTITION BY country_region, calendar_year),
            2
        ) AS pct_by_channels
    FROM sales_by_channel
)
-- Step 3: use LAG to bring in last year's % for the same region+channel
SELECT
    country_region,
    calendar_year,
    channel_desc,
    amount_sold,
    pct_by_channels,
    LAG(pct_by_channels) OVER (
        PARTITION BY country_region, channel_desc
        ORDER BY calendar_year
    ) AS pct_previous_period,
    pct_by_channels - LAG(pct_by_channels) OVER (
        PARTITION BY country_region, channel_desc
        ORDER BY calendar_year
    ) AS pct_diff
FROM sales_with_pct
ORDER BY country_region, calendar_year, channel_desc;

-- TASK 2 — Sales report for weeks 49-51 of 1999
-- Needs:
--   - cum_sum: running total within each week (resets every Monday)
--   - centered_3_day_avg: prev + current + next day average
--     Monday case: 4 days (Sat, Sun, Mon, Tue)
--     Friday case: 4 days (Thu, Fri, Sat, Sun)
--
-- Tricky part: the task says calculations must be accurate at the start of
-- week 49 and the end of week 51. That means Mon of week 49 needs Sat/Sun
-- from week 48, and Fri of week 51 needs Sat/Sun from week 52.
-- So I pull weeks 48-52 in the CTE and filter the result down to 49-51 at the end.

WITH daily_sales AS (
    SELECT
        t.calendar_week_number,
        t.time_id,
        t.day_name,
        SUM(s.amount_sold) AS sales
    FROM sales s
    JOIN times t ON s.time_id = t.time_id
    WHERE t.calendar_year = 1999
      AND t.calendar_week_number BETWEEN 48 AND 52
    GROUP BY t.calendar_week_number, t.time_id, t.day_name
),
with_windows AS (
    SELECT
        calendar_week_number,
        time_id,
        day_name,
        sales,
        -- running total per week
        SUM(sales) OVER (
            PARTITION BY calendar_week_number
            ORDER BY time_id
        ) AS cum_sum,
        -- centered moving average with special cases for Mon and Fri
        CASE
            WHEN day_name = 'Monday' THEN
                ( LAG(sales, 2)  OVER (ORDER BY time_id)   -- Saturday
                + LAG(sales, 1)  OVER (ORDER BY time_id)   -- Sunday
                + sales                                    -- Monday
                + LEAD(sales, 1) OVER (ORDER BY time_id)   -- Tuesday
                ) / 4.0
            WHEN day_name = 'Friday' THEN
                ( LAG(sales, 1)  OVER (ORDER BY time_id)   -- Thursday
                + sales                                    -- Friday
                + LEAD(sales, 1) OVER (ORDER BY time_id)   -- Saturday
                + LEAD(sales, 2) OVER (ORDER BY time_id)   -- Sunday
                ) / 4.0
            ELSE
                -- regular case: previous + current + next
                ( LAG(sales, 1)  OVER (ORDER BY time_id)
                + sales
                + LEAD(sales, 1) OVER (ORDER BY time_id)
                ) / 3.0
        END AS centered_3_day_avg
    FROM daily_sales
)
SELECT
    calendar_week_number,
    time_id,
    day_name,
    sales,
    cum_sum,
    ROUND(centered_3_day_avg, 2) AS centered_3_day_avg
FROM with_windows
WHERE calendar_week_number BETWEEN 49 AND 51
ORDER BY time_id;

-- TASK 3 — Three frame-clause examples (ROWS, RANGE, GROUPS)

-- ---------- Example 1: ROWS ----------
-- 7-day rolling average of daily sales.
-- ROWS counts physical rows in the result set, not date values.
-- I want exactly 7 rows: current day + 6 preceding rows, regardless of
-- whether dates are continuous. If a day has no sales it's just missing
-- from the result and ROWS still gives me 7 actual data points.
-- Use ROWS when the question is "my last N data points".

SELECT
    t.time_id,
    SUM(s.amount_sold) AS daily_sales,
    AVG(SUM(s.amount_sold)) OVER (
        ORDER BY t.time_id
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS rolling_7day_avg
FROM sales s
JOIN times t ON s.time_id = t.time_id
WHERE t.calendar_year = 1999
  AND t.calendar_month_number = 12
GROUP BY t.time_id
ORDER BY t.time_id;


-- ---------- Example 2: RANGE ----------
-- Sales in the actual last 7 calendar days.
-- RANGE uses the value of the ORDER BY column, not row positions.
-- With an INTERVAL, "6 PRECEDING" means "6 calendar days before this row's
-- date". If a day is missing from the data, ROWS would silently stretch the
-- window further back in calendar time. RANGE with INTERVAL gives the exact
-- 7-calendar-day window regardless.
-- Use RANGE when the window is defined by actual values (especially dates).

SELECT
    t.time_id,
    SUM(s.amount_sold) AS daily_sales,
    SUM(SUM(s.amount_sold)) OVER (
        ORDER BY t.time_id
        RANGE BETWEEN INTERVAL '6' DAY PRECEDING AND CURRENT ROW
    ) AS sales_last_7_calendar_days
FROM sales s
JOIN times t ON s.time_id = t.time_id
WHERE t.calendar_year = 1999
  AND t.calendar_month_number = 12
GROUP BY t.time_id
ORDER BY t.time_id;


-- ---------- Example 3: GROUPS ----------
-- 3-month moving average where each month is one peer group.
-- GROUPS treats rows with the same ORDER BY value as one peer group and
-- counts groups, not rows. Each row here is one day, but I want the average
-- to step by whole months. GROUPS BETWEEN 2 PRECEDING AND CURRENT ROW means
-- "this month plus the 2 previous months" regardless of how many days each
-- month contains.
-- Why not RANGE? RANGE does arithmetic on the value (current_month - 2). If
-- a whole month is missing from the data, GROUPS still goes back 2 actual
-- peer groups; RANGE would just subtract 2 from the number.
-- Use GROUPS when rows naturally cluster into peer groups (months, weeks,
-- categories) and you want to step by whole groups.

SELECT
    t.calendar_month_number,
    t.day_number_in_month,
    SUM(s.amount_sold) AS daily_sales,
    AVG(SUM(s.amount_sold)) OVER (
        ORDER BY t.calendar_month_number
        GROUPS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS avg_over_current_and_2_prev_months
FROM sales s
JOIN times t ON s.time_id = t.time_id
WHERE t.calendar_year = 1999
GROUP BY t.calendar_month_number, t.day_number_in_month
ORDER BY t.calendar_month_number, t.day_number_in_month;
