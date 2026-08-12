SELECT 'prices' AS table_name, COUNT(*), MIN(date), MAX(date) FROM prices
UNION ALL
SELECT 'garch_forecasts' AS table_name, COUNT(*), MIN(date), MAX(date) FROM garch_forecasts;