# GARCH Volatility Targeting Model

A systematic trading strategy that uses a GARCH(1,1) volatility forecast to
dynamically size QQQ exposure, backtested against a buy-and-hold QQQ benchmark.

## What this project does

The pipeline has two distinct parts:

1. **Volatility forecasting** — a GARCH(1,1) model is fit walk-forward on QQQ
   log returns to produce a 1-step-ahead forecast of *how volatile* QQQ will
   be. This part makes no directional (up/down) prediction whatsoever.
2. **Volatility-targeting trading strategy** — that forecast is used to size
   a daily position in QQQ: exposure is scaled *inversely* to forecasted
   volatility (more exposure when the model expects calm markets, less when
   it expects turbulence), capped at a maximum leverage multiple. The
   resulting daily returns are then backtested against plain buy-and-hold.

## Pipeline

| Step | Script | Purpose |
|---|---|---|
| 1 | `data_ingestion.py` | Pulls daily OHLCV for QQQ, computes log returns |
| 2 | `baseline_volatility.py` | Naive rolling realized-volatility baseline |
| 3 | `garch_model.py` | Walk-forward GARCH(1,1) 1-day-ahead volatility forecasts |
| 4 | `01_schema.sql` | Creates `prices`, `backtest_runs`, `garch_forecasts` tables |
| 5 | `02_load_prices.sql` | Loads step 1 output into `prices` |
| 6 | `03_load_garch_forecasts.sql` | Loads step 3 output, creates a `backtest_runs` row |
| 7 | `04_vol_targeting.sql` | Computes position weights from the forecasts |
| 8 | `05_evalutation.sql` | Backtests strategy vs. buy-and-hold, computes Sharpe/drawdown/Calmar |

## Configuration (this run)

| Parameter | Value |
|---|---|
| Ticker | QQQ |
| GARCH training window | 756 trading days (~3 years) |
| Refit frequency | Every day |
| Target annualized volatility | 10% |
| Max leverage (`weight_clip`) | 1.5x |
| Out-of-sample period | 2018-01-04 to 2026-08-10 |
| Forecast/backtest days | 2,160 forecasted / 2,159 evaluated (first day dropped by the 1-day position lag) |

## Model specification

The forecast is a zero-mean GARCH(1,1) with normally distributed
innovations, matching what's implemented in `garch_model.py`
(`arch_model(..., vol="Garch", p=1, q=1, mean="Zero", dist="Normal")`):

**Return equation:**

$$r_t = \epsilon_t, \qquad \epsilon_t = \sigma_t z_t, \qquad z_t \sim N(0,1)$$

**Conditional variance equation:**

$$\sigma_t^2 = \omega + \alpha \epsilon_{t-1}^2 + \beta \sigma_{t-1}^2$$

Where:

| Symbol | Meaning |
|---|---|
| $\sigma_t^2$ | Forecasted (conditional) variance for day $t$ — the model's target output |
| $\omega$ (omega) | Constant term — the long-run baseline level of variance |
| $\alpha$ (alpha) | Weight on yesterday's squared shock — how strongly a recent surprise moves the forecast |
| $\epsilon_{t-1}^2$ | Yesterday's squared return shock (residual²) |
| $\beta$ (beta) | Weight on yesterday's forecasted variance — how much "memory" the model has |
| $\sigma_{t-1}^2$ | Yesterday's forecasted variance |

The reported **persistence** metric is $\alpha + \beta$: how slowly a volatility shock
decays back toward the long-run average. A value near 1.0 means shocks fade
very slowly (high memory); a value ≥ 1.0 implies the variance process is
non-stationary (explosive), which is why `garch_model.py` flags any date
where this occurs.

Each day's fitted ω, α, β come from re-estimating the model on a rolling
756-day (~3-year) trailing window of returns, then forecasting one step
ahead — this is what makes it a *walk-forward* forecast rather than a
single static fit.

## Position sizing (vol targeting) formula

Each day's position weight is computed from the GARCH forecast as:

$$w_t = \min\left(\frac{\sigma_{target}}{\hat{\sigma}_t},\ w_{max}\right)$$

Where:

| Symbol | Meaning | This run |
|---|---|---|
| $w_t$ | Position weight (exposure coefficient) for day $t$ compared to the "Buy & Hold" strategy| — |
| $\sigma_{target}$ | Target annualized portfolio volatility | 10% |
| $\hat{\sigma}_t$ | GARCH-forecasted annualized volatility for day $t$ | — |
| $w_{max}$ | Maximum allowed leverage (`weight_clip`) | 1.5x |

The realized weight actually traded on day $t$ is this value computed from
the *prior* day's information, shifted forward by one trading day
(`LAG(weight_raw)` in `04_vol_targeting.sql`), so the position never uses
same-day information.

## GARCH(1,1) model diagnostics

| Metric | Value |
|---|---|
| Mean forecasted vol | 21.51% |
| Min forecasted vol | 9.85% |
| Max forecasted vol | 122.71% |
| Latest forecasted vol | 24.78% |
| Mean alpha (shock weight) | 0.1295 |
| Mean beta (memory weight) | 0.8387 |
| Mean persistence (alpha + beta) | 0.9682 |
| Refit rate | 2,160 / 2,160 days (every day) |
| Stationarity | 1 date exhibited persistence ≥ 1.0 (explosive variance) — isolated case, not a broad model breakdown |

Persistence close to but generally under 1.0 is expected for equity index
volatility — it reflects strong (but not infinite) memory in the variance
process, i.e. volatility shocks decay slowly rather than reverting instantly.

## Results: strategy vs. buy-and-hold

| Metric | Buy & hold QQQ | Vol-targeting strategy |
|---|---|---|
| Sharpe ratio | 0.7595 | **0.9260** |
| Max drawdown | -35.12% | **-15.10%** |
| Annualized return | **19.94%** | 10.15% |
| Calmar ratio | 0.5679 | **0.6719** |

(n = 2,159 trading days, risk-free rate assumed 0%)

## Interpretation

The vol-targeting strategy delivered a better risk-adjusted return than
buy-and-hold on every risk-adjusted metric: a higher Sharpe ratio, roughly
half the maximum drawdown, and a higher Calmar ratio. This is the expected
signature of volatility targeting — cutting exposure as GARCH senses rising
volatility tends to reduce exposure heading into turbulent, often
drawdown-heavy periods, and re-levering during calm stretches.

The trade-off is raw return: the strategy's annualized return (10.15%) is
about half of buy-and-hold's (19.94%). This isn't a sign the strategy
"failed" — it's a direct consequence of the 10% target volatility being set
below QQQ's actual realized volatility over this period (mean forecasted vol
was 21.51%), so the strategy was structurally *under*-exposed relative to a
100%-QQQ position for most of the sample, even after the 1.5x leverage cap.
A higher `target_vol` (or higher `weight_clip`) would close some of that
return gap, at the cost of a smaller drawdown improvement.

## Limitations

- No transaction costs, slippage, or financing/borrowing costs are modeled
  — the `weight_clip = 1.5` leverage is assumed frictionless.
- Single ticker (QQQ), single parameter configuration — no walk-forward
  validation of the strategy's own hyperparameters (`target_vol`,
  `weight_clip`, GARCH window length).
- Risk-free rate is assumed to be 0% in the Sharpe ratio calculation.
- Backtest, not live trading — results reflect historical fit, not a
  forward guarantee.

## How to reproduce

**Steps 1–3 (Python):**

```bash
python data_ingestion.py --ticker QQQ --start 2015-01-01
python baseline_volatility.py
python garch_model.py --window 756 --refit-every 1
```

**Steps 4–8 (SQL):** run these directly against a local PostgreSQL 14+
installation, in order, using whichever client you prefer (`psql`,
pgAdmin, DBeaver, etc.) — no Python involved for this part.

1. `01_schema.sql`
2. `02_load_prices.sql` — **before running**, replace the hardcoded
   absolute path in the `COPY` statement with your own local path to
   `prices.csv` (the file already has a comment marking where to edit it)
3. `03_load_garch_forecasts.sql` — **before running**, same as above:
   replace the hardcoded path in the `COPY` statement with your own local
   path to `garch_forecasts.csv`
4. `04_vol_targeting.sql` — edit `target_vol` / `weight_clip` if you want
   to test a different configuration
5. `05_evalutation.sql`
