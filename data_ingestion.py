import argparse
from pathlib import Path

import numpy as np 
import pandas as pd
import yfinance as yf

def fetch_ohlcv(ticker: str, start: str, end: str | None = None) -> pd.DataFrame:
    df = yf.download(ticker, start=start, end=end, auto_adjust=True, progress=False)

    if df.empty:
        raise ValueError(f"No data returned for '{ticker}'. Check ticker/date range.")

    if isinstance(df.columns, pd.MultiIndex):
        df.columns = df.columns.get_level_values(0)

    df.index.name = "date"
    df = df.dropna(how="all")
    return df

def compute_log_returns(df: pd.DataFrame, price_col: str = "Close") -> pd.DataFrame:
    out = df.copy()
    out["log_return"] = np.log(out[price_col] / out[price_col].shift(1))
    out = out.dropna(subset=["log_return"])
    return out

def data_quality_report(df: pd.DataFrame, ticker: str) -> None:
    print(f"\n--- Data Quality Report: {ticker} ---")
    print(f"Data range      : {df.index.min().date()} to {df.index.max().date()}")
    print(f"Trading days    : {len(df)}")
    print(f"Missing values  : {df['log_return'].isna().sum()}")
    print(f"Mean log return : {df['log_return'].mean():.6f}")
    print(f"Std log return  : {df['log_return'].std():.6f}")
    print(f"Ann. vol (naive): {df['log_return'].std() * np.sqrt(252):.4f}")

    extreme = df[df["log_return"].abs() > 0.10]
    if not extreme.empty:
        print(f"Dats with |log return| > 10%: {len(extreme)}")
        print(extreme[["log_return"]])

def main():
    parser = argparse.ArgumentParser(description="Step 1: Data ingestion")
    parser.add_argument("--ticker", default="QQQ", help="Ticker symbol")
    parser.add_argument("--start", default="2015-01-01", help="Start date YYYY-MM-DD")
    parser.add_argument("--end", default=None, help="End date YYYY-MM-DD (default: today)")
    parser.add_argument("--output", default="data/prices.csv", help="Output CSV path")
    args = parser.parse_args()

    Path(args.output).parent.mkdir(parents=True, exist_ok=True)

    df = fetch_ohlcv(args.ticker, args.start, args.end)
    df = compute_log_returns(df)
    data_quality_report(df, args.ticker)

    df.to_csv(args.output)

    df.to_csv(args.output)
    print(f"\nSaved {len(df)} rows to {args.output}")

if __name__ == "__main__":
    main()