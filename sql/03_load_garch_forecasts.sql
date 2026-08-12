-- ============================================================
-- Load step 3/6 output (garch_forecasts.csv) into backtest_runs
-- and garch_forecasts. Edit ticker/window/refit_every and the
-- file path below before running.
-- ============================================================

BEGIN;

CREATE TEMP TABLE forecasts_staging (
    date            DATE,
    open            NUMERIC,
    high            NUMERIC,
    low             NUMERIC,
    close           NUMERIC,
    volume          BIGINT,
    log_return      NUMERIC,
    forecasted_vol  NUMERIC,
    omega           NUMERIC,
    alpha           NUMERIC,
    beta            NUMERIC,
    refit_day       BOOLEAN,
    persistence     NUMERIC
);

COPY forecasts_staging
FROM 'C:\Users\joong\OneDrive\Documents\Personal Projects\GARCH Volatility Targeting Model\data\garch_forecasts.csv' --REPLACE WITH YOUR OWN ABSOLUTE PATH FOR "garch_forecasts.csv"
WITH (FORMAT csv, HEADER true);

-- Data-modifying CTE: creates one new backtest_runs row, then feeds its
-- generated run_id straight into the garch_forecasts insert -- one
-- statement, no need to manually capture and paste an ID between steps.
WITH new_run AS (
    INSERT INTO backtest_runs (ticker, window_size, refit_every, start_date, end_date)
    SELECT 'QQQ', 756, 1, MIN(date), MAX(date)
    FROM forecasts_staging
    RETURNING run_id
)

INSERT INTO garch_forecasts (run_id, ticker, date, forecasted_vol, omega, alpha, beta, persistence, refit_day)
SELECT new_run.run_id, 'QQQ', s.date, s.forecasted_vol, s.omega, s.alpha, s.beta, s.persistence, s.refit_day
FROM forecasts_staging s
CROSS JOIN new_run;

COMMIT;