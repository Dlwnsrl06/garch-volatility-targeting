-- ============================================================
-- Step 7: Evaluation
-- Sharpe ratio, max drawdown, Calmar ratio: vol-targeting
-- strategy vs. buy-and-hold benchmark.
-- Run after 04_vol_targeting.sql.
-- ============================================================

-- 1) Report

WITH target_run AS (
    SELECT MAX(run_id) AS run_id FROM backtest_runs
),

daily_returns AS (
    SELECT 
        g.date,
        p.log_return,
        g.weight,
        EXP(p.log_return) - 1 AS simple_return
    FROM garch_forecasts g 
    JOIN prices p ON p.ticker = g.ticker AND p.date = g.date
    CROSS JOIN target_run t
    WHERE g.run_id = t.run_id
    AND g.weight IS NOT NULL
),

strat_returns AS (
    SELECT
        date,
        log_return AS bh_log_return,
        CASE 
            WHEN 1 + weight * simple_return <= 0 THEN NULL --guard: undefined for a >100% single-day loss
            ELSE LN(1 + weight * simple_return)
        END AS strat_log_return
    FROM daily_returns
),

equity_curve AS (
    SELECT
        date,
        bh_log_return,
        strat_log_return,
        EXP(SUM(bh_log_return)  OVER (ORDER BY date ROWS UNBOUNDED PRECEDING)) AS bh_equity,
        EXP(SUM(strat_log_return) OVER (ORDER BY date ROWS UNBOUNDED PRECEDING)) AS strat_equity
    FROM strat_returns
),

drawdowns AS (
    SELECT
        date, 
        bh_equity    / MAX(bh_equity)    OVER (ORDER BY date ROWS UNBOUNDED PRECEDING) - 1 AS bh_drawdown,
        strat_equity / MAX(strat_equity) OVER (ORDER BY date ROWS UNBOUNDED PRECEDING) - 1 AS strat_drawdown
    FROM equity_curve 
),

stats AS (
    SELECT
        COUNT(*)                         AS n_days,
        AVG(sr.bh_log_return)            AS bh_mean_daily,
        STDDEV_SAMP(sr.bh_log_return)    AS bh_std_daily,
        AVG(sr.strat_log_return)         AS strat_mean_daily,
        STDDEV_SAMP(sr.strat_log_return) AS strat_std_daily,
        MIN(dd.bh_drawdown)              AS bh_max_drawdown,
        MIN(dd.strat_drawdown)           AS strat_max_drawdown
    FROM strat_returns sr
    JOIN drawdowns dd USING (date)
)

SELECT
    n_days,
    -- Sharpe: mean/std of daily log returns, annualized by sqrt(252).
    -- Risk-free rate assumed 0 -- standard simplification for a project
    -- backtest; a bank-grade version would subtract the daily T-bill rate.
    ROUND((bh_mean_daily / NULLIF(bh_std_daily, 0) * SQRT(252))::NUMERIC, 4)       AS bh_sharpe,
    ROUND((strat_mean_daily / NULLIF(strat_std_daily, 0) * SQRT(252))::NUMERIC, 4) AS strat_sharpe,
    ROUND(bh_max_drawdown::NUMERIC, 4)    AS bh_max_drawdown,
    ROUND(strat_max_drawdown::NUMERIC, 4) AS strat_max_drawdown,
    ROUND((EXP(bh_mean_daily * 252) - 1)::NUMERIC, 4)    AS bh_annualized_return,
    ROUND((EXP(strat_mean_daily * 252) - 1)::NUMERIC, 4) AS strat_annualized_return,
    ROUND(((EXP(bh_mean_daily * 252) - 1) / NULLIF(ABS(bh_max_drawdown), 0))::NUMERIC, 4)       AS bh_calmar,
    ROUND(((EXP(strat_mean_daily * 252) - 1) / NULLIF(ABS(strat_max_drawdown), 0))::NUMERIC, 4) AS strat_calmar
FROM stats;

-- 2) Persist strategy metrics into backtest_runs

BEGIN;

WITH target_run AS (
    SELECT MAX(run_id) AS run_id FROM backtest_runs
),

daily_returns AS (
    SELECT
        g.date,
        g.weight,
        EXP(p.log_return) - 1 AS simple_return
    FROM garch_forecasts g 
    JOIN prices P ON p.ticker = g.ticker AND p.date = g.date
    CROSS JOIN target_run t 
    WHERE g.run_id = t.run_id
    AND g.weight IS NOT NULL
),

strat_returns AS (
    SELECT
        date,
        CASE
            WHEN 1 + weight * simple_return <= 0 THEN NULL
            ELSE LN(1 + weight * simple_return)
        END AS strat_log_return
    FROM daily_returns
),

equity_curve AS (
    SELECT
        date,
        EXP(SUM(strat_log_return) OVER (ORDER BY date ROWS UNBOUNDED PRECEDING)) AS strat_equity
    FROM strat_returns
),

drawdowns AS (
    SELECT
        date,
        strat_equity / MAX(strat_equity) OVER (ORDER BY date ROWS UNBOUNDED PRECEDING) - 1 AS strat_drawdown
    FROM equity_curve
),

stats AS (
    SELECT
        AVG(sr.strat_log_return)         AS strat_mean_daily,
        STDDEV_SAMP(sr.strat_log_return) AS strat_std_daily,
        MIN(dd.strat_drawdown)           AS strat_max_drawdown
    FROM strat_returns sr
    JOIN drawdowns dd USING (date)
)

UPDATE backtest_runs b 
SET
    sharpe_ratio = (s.strat_mean_daily / NULLIF(s.strat_std_daily, 0)) * SQRT(252),
    max_drawdown = s.strat_max_drawdown,
    calmar_ratio = (EXP(s.strat_mean_daily * 252) -1) / NULLIF(ABS(s.strat_max_drawdown), 0)
FROM stats s, target_run t 
WHERE b.run_id = t.run_id;

COMMIT;

-- Sanity Check
SELECT run_id, ticker, window_size, refit_every, target_vol, weight_clip, sharpe_ratio, max_drawdown, calmar_ratio
FROM backtest_runs
ORDER BY run_id DESC
LIMIT 1;