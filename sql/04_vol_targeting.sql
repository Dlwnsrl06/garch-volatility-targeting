-- ============================================================
-- Step 5: Vol-Targeting Weights
-- weight = target_vol / forecasted_vol, clipped at weight_clip,
-- then shifted by 1 day so day t's position uses only
-- information available at the close of day t-1.
-- Run after schema.sql, load_prices.sql, load_garch_forecasts.sql.
-- You can edit target_vol and weight_clip to your preference 
-- ============================================================

BEGIN;

-- 1) Record this run's vol-targeting configuration. These columns were
--    reserved as NULL back in the 01_schema for this purpose 
UPDATE backtest_runs
SET target_vol = 0.10, -- 10% annualized target -> can be modified
    weight_clip = 1.5  -- max leveraged multiplier -> can be modified
WHERE run_id = (SELECT MAX(run_id) FROM backtest_runs); -- grabs the most recent run

-- 2) Add weight columns to garch_forecasts if they don't exist
ALTER TABLE garch_forecasts ADD COLUMN IF NOT EXISTS weight_raw NUMERIC;
ALTER TABLE garch_forecasts ADD COLUMN IF NOT EXISTS weight    NUMERIC;

-- 3) Compute the same-day vol-targeting weight, clipped at weight_clip
--    NULLIF guards against a division error in the unlikely case
--    forecasted_vol is ever exactly zero
UPDATE garch_forecasts g
SET weight_raw = LEAST(b.target_vol / NULLIF(g.forecasted_vol, 0), b.weight_clip)
FROM backtest_runs b
WHERE g.run_id = b.run_id
AND g.run_id = (SELECT MAX(run_id) FROM backtest_runs);

-- 4) Shift weight_raw forward by one trading day, per {run_id, ticker}
--    Window functions can't sit directly in an UPDATE's SET list, so the 
--    LAG() is computed in a subquery and joined back on the same keys
UPDATE garch_forecasts g
SET weight = shifted.weight_shifted
FROM (
    SELECT
        run_id, 
        ticker,
        date,
        LAG(weight_raw) OVER (PARTITION BY run_id, ticker ORDER BY date) AS weight_shifted
    FROM garch_forecasts
    WHERE run_id = (SELECT MAX(run_id) FROM backtest_runs)
) shifted
WHERE g.run_id = shifted.run_id
AND g.ticker = shifted.ticker
AND g.date = shifted.date;

COMMIT;

-- 5) Sanity check: the first row should show weight = NULL (no prior day to shift from)
--    Everything after should sit between [0,1.5]
SELECT date, forecasted_vol, weight_raw, weight
FROM garch_forecasts
WHERE run_id = (SELECT MAX(run_id) FROM backtest_runs)
ORDER BY date
LIMIT 5;

