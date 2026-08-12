-- ============================================================
-- Load step 1 output (prices.csv) into the prices table.
-- Edit the file path and ticker below before running.
-- ============================================================

BEGIN;

CREATE TEMP TABLE prices_staging (
    date        DATE,
    open        NUMERIC,
    high        NUMERIC,
    low         NUMERIC,
    close       NUMERIC,
    volume      BIGINT,
    log_return  NUMERIC
);

COPY prices_staging (date, open, high, low, close, volume, log_return)
FROM 'C:\Users\joong\OneDrive\Documents\Personal Projects\GARCH Volatility Targeting Model\data\prices.csv' --REPLACE WITH YOUR OWN ABSOLUTE PATH FOR "prices.csv"
WITH (FORMAT csv, HEADER true);

INSERT INTO prices (ticker, date, open, high, low, close, volume, log_return)
SELECT 'QQQ', date, open, high, low, close, volume, log_return
FROM prices_staging
ON CONFLICT (ticker, date) DO UPDATE SET
    open       = EXCLUDED.open,
    high       = EXCLUDED.high,
    low        = EXCLUDED.low,
    close      = EXCLUDED.close,
    volume     = EXCLUDED.volume,
    log_return = EXCLUDED.log_return;

COMMIT;