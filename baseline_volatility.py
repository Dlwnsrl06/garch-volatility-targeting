import argparse
from pathlib import Path
import numpy as np 
import pandas as pd

def load_price_data(path: str) -> pd.DataFrame:
    df = pd.read_csv(path, index_col="date", parse_dates=True)
    if "log_return" not in df.columns:
        raise ValueError(
            f"'log_return' column not found in {path}. Run step 1 (data_ingestion.py) first."
        )
    return df

def compute_realized_volatility(
        df: pd.DataFrame,
        window: int = 21,
        trading_days: int = 252,
        shift_for_forecast: bool = False,
) -> pd.DataFrame:
    out = df.copy()
    vol = out["log_return"].rolling(window=window).std(ddof=1) * np.sqrt(trading_days)

    if shift_for_forecast:
        vol = vol.shift(1)

    out["realized_vol"] = vol
    out = out.dropna(subset=["realized_vol"])
    return out

def volatility_report(df: pd.DataFrame, ticker: str, window: int) -> None:
    print(f"\n--- Baseline Volatility Report: {ticker} (rolling {window}d, annualized) ---")
    print(f"Data range        : {df.index.min().date()} to {df.index.max().date()}")
    print(f"Observations      : {len(df)}")
    print(f"Mean realized vol : {df['realized_vol'].mean():.4f}")
    print(f"Min realized vol  : {df['realized_vol'].min():.4f}")
    print(f"Max realized vol  : {df['realized_vol'].max():.4f}")
    print(f"Latest realized vol: {df['realized_vol'].iloc[-1]:.4f}")

    vol_autocorr = df["realized_vol"].autocorr(lag=1)
    ret_autocorr = df["log_return"].autocorr(lag=1)
    print(f"Lag-1 autocorr, realized vol : {vol_autocorr:.4f}")
    print(f"Lag-1 autocorr, log returns  : {ret_autocorr:.4f}")

def main():
    parser = argparse.ArgumentParser(description="Step 2: Baseline realized volatility")
    parser.add_argument("--input", default="data/prices.csv", help="Input CSV from step 1")
    parser.add_argument("--ticker", default="QQQ", help="Ticker symbol (for report labeling)")
    parser.add_argument("--window", type=int, default=21, help="Rolling window size (trading days)")
    parser.add_argument(
        "--as-forecast",
        action="store_true",
        help="Shift realized vol by 1 day so it's usable as a naive next-day forecast",
    )
    parser.add_argument("--output", default="data/baseline_vol.csv", help="Output CSV path")
    args = parser.parse_args()

    Path(args.output).parent.mkdir(parents=True, exist_ok=True)

    df = load_price_data(args.input)
    df = compute_realized_volatility(df, window=args.window, shift_for_forecast=args.as_forecast)
    volatility_report(df, args.ticker, args.window)

    df.to_csv(args.output)
    print(f"\nSaved {len(df)} rows to {args.output}")

if __name__ == "__main__":
    main()