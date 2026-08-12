-- ============================================================
-- Schema: GARCH-Based Volatility Targeting Strategy
-- Tables: prices, backtest_runs, garch_forecasts
-- Target: PostgreSQL 14+
-- ============================================================

-- Daily OHLCV + computed log returns, keyed by ticker + date.
-- Composite PK supports multiple tickers without a schema change later.

CREATE TABLE IF NOT EXISTS prices (
    ticker      VARCHAR(10) NOT NULL,
    date        DATE NOT NULL,
    open        NUMERIC,
    high        NUMERIC,
    low         NUMERIC,
    close       NUMERIC,
    volume      BIGINT,
    log_return  NUMERIC,
    PRIMARY KEY (ticker, date)
);

-- One row per backtest/experiment configuration.
-- target_vol, weight_clip (step 5) and sharpe/drawdown/calmar (step 7)
-- start as NULL and get filled in by later steps via UPDATE.
CREATE TABLE IF NOT EXISTS backtest_runs (
    run_id          INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ticker          VARCHAR(10) NOT NULL,
    window_size     INTEGER NOT NULL,
    refit_every     INTEGER NOT NULL,
    start_date      DATE,
    end_date        DATE,
    target_vol      NUMERIC,
    weight_clip     NUMERIC,
    sharpe_ratio    NUMERIC,
    max_drawdown    NUMERIC,
    calmar_ratio    NUMERIC,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

-- One row per (run, date): the GARCH(1,1) walk-forward output.
-- Tied to backtest_runs so multiple experiments can coexist.
CREATE TABLE IF NOT EXISTS garch_forecasts (
    run_id          INTEGER NOT NULL REFERENCES backtest_runs(run_id) ON DELETE CASCADE,
    ticker          VARCHAR(10) NOT NULL,
    date            DATE NOT NULL,
    forecasted_vol  NUMERIC,
    omega           NUMERIC,
    alpha           NUMERIC,
    beta            NUMERIC,
    persistence     NUMERIC,
    refit_day       BOOLEAN,
    PRIMARY KEY (run_id, ticker, date)
);