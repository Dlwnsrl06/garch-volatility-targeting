import argparse
import warnings
from pathlib import Path
import numpy as np
import pandas as pd
from arch import arch_model

#Suppress arch estimation convergence warnings in loops
warnings.filterwarnings("ignore")

def load_price_data(path: str) -> pd.DataFrame:
    df = pd.read_csv(path, index_col="date", parse_dates=True)
    if "log_return" not in df.columns:
        raise ValueError(
            f"'log_return'column not found in {path}. Run step 1 (data_ingestion) first."
        )
    return df

def fit_walk_forward_garch(
    df: pd.DataFrame,
    window: int = 756, #3-year rolling training window
    trading_days: int = 252,
) -> pd.DataFrame:
    """
    Executes a daily rolling walk-forward fit for GARCH(1,1).
    Forecasts 1-step-ahead conditional volatility for each day out-of-sample.
    """
    returns = df["log_return"].dropna()
    n = len(returns)

    if n <= window:
        raise ValueError(
            f"Dataset has {n} rows, but window size is {window}. Increase data range or decrease window."
        )

    # Scale returns up by 100 to prevent optimizer convergence failure on tiny omega value
    scaled_returns = returns * 100.0

    forecasts = []
    dates = []
    omegas = []
    alphas = []
    betas = []

    print(f"Running rolling GARCH(1,1) walk-foward validation across {n - window} days...")

    for i in range(window, n):
        # Rolling training window: strictly historical data up to t-1
        train_slice = scaled_returns.iloc[i - window : i]
        current_date = returns.index[i]

        # Zero-mean GARCH(1,1) with Normal distribution
        model = arch_model(train_slice, vol="Garch", p=1, q=1, mean="Zero", dist="Normal")
        res = model.fit(disp="off", show_warning=False)

        #Extract 1-step-ahead variance forecase for day t
        #red.forecast() projects forward starting from the last date in train_slice
        var_forecast_scaled = res.forecast(horizon=1).variance.iloc[-1, 0]

        #Convert scaled variance back to unscaled annualized volatility
        # Variance scale: / 10000 -> Volatility scale: / 100 -> Annualized: * sqrt(252)
        vol_forecast_daily = np.sqrt(var_forecast_scaled) / 100.0
        vol_forecast_annualized = vol_forecast_daily * np.sqrt(trading_days)

        # Collect parameters & forecasts
        forecasts.append(vol_forecast_annualized)
        dates.append(current_date)

        # Downscale omega back to true return units
        omegas.append(res.params["omega"] / 10000.0)
        alphas.append(res.params["alpha[1]"])
        betas.append(res.params["beta[1]"])

    out_df = pd.DataFrame(
        {
            "forecasted_vol": forecasts,
            "omega": omegas,
            "alpha": alphas,
            "beta": betas,
        },
        index=pd.DatetimeIndex(dates, name="date"),
    )

    #Calculate persistence (alpha + beta)
    out_df["persistence"] = out_df["alpha"] + out_df["beta"]

    #Join with original pricing & return date
    result = df.join(out_df, how="inner")
    return result

def garch_report(df: pd.DataFrame, ticker: str) -> None:
    print(f"\n--- GARCH(1,1) Forecast Report: {ticker} ---")
    print(f"Out-of-sample dates : {df.index.min().date()} to {df.index.max().date()}")
    print(f"Forecast count      : {len(df)}")
    print(f"Mean forecasted vol : {df['forecasted_vol'].mean():.4f}")
    print(f"Min forecasted vol  : {df['forecasted_vol'].min():.4f}")
    print(f"Max forecasted vol  : {df['forecasted_vol'].max():.4f}")
    print(f"Latest forecast vol : {df['forecasted_vol'].iloc[-1]:.4f}")

    print(f"\n--- Model Parameters (Averages across Walk-Forward Window) ---")
    print(f"Mean Alpha (shock)  : {df['alpha'].mean():.4f}")
    print(f"Mean Beta (memory)  : {df['beta'].mean():.4f}")
    print(f"Mean Persistence    : {df['persistence'].mean():.4f}")

    non_stationary = df[df["persistence"] >= 1.0]
    if not non_stationary.empty:
        print(f"\nWARNING: {len(non_stationary)} dates exhibited explosive persistence (alpha + beta >= 1.0)")
    else:
        print("\nStationarity Check : PASSED (alpha + beta < 1.0 for all iterations)")

def main():
    parser = argparse.ArgumentParser(description="Step 3: GARCH(1,1) Volatility Forecasting")
    parser.add_argument("--input", default="data/prices.csv", help="Input CSV from step 1")
    parser.add_argument("--ticker", default="QQQ", help="Ticker symbol")
    parser.add_argument("--window", type=int, default=756, help="Rolling training window size (3 years = 756 days)")
    parser.add_argument("--output", default="data/garch_forecasts.csv", help="Output CSV path")
    args = parser.parse_args()

    Path(args.output).parent.mkdir(parents=True, exist_ok=True)

    df = load_price_data(args.input)
    forecast_df = fit_walk_forward_garch(df, window=args.window)
    garch_report(forecast_df, args.ticker)

    forecast_df.to_csv(args.output)
    print(f"\nSaved {len(forecast_df)} rows to {args.output}")


if __name__ == "__main__":
    main()