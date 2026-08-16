# Backlog: adtnTracker

This file contains the initial backlog items and issue payloads for evansh/adtnTracker.

## Issues to create (direct issue creation script included in scripts/create_issues.sh)

1) Evaluate TD Ameritrade developer access & onboarding

- Priority: P0
- Size: S
- Labels: backend, infra, P0, size/S
- Assignee: @evansh
- Description:
  - Verify current TD API status (post-acquisition), OAuth requirements, scopes for options and trading, rate limits, and app registration steps.
  - Document how to register an app and sample auth flow (OAuth). Note any limitations and rate limits.
  - Output: `docs/integrations/td_ameritrade.md` with concrete setup steps and recommended retry/caching strategy.
- Acceptance criteria:
  - `docs/integrations/td_ameritrade.md` added to repo with concrete setup steps, scopes, and rate-limit notes.


2) Integrate yfinance for equity historicals (daily + intraday where available)

- Priority: P0
- Size: M
- Labels: data, backend, P0, size/M
- Assignee: @evansh
- Description:
  - Implement a downloader module to fetch and cache ADTN OHLCV using `yfinance`.
  - Support daily full history and intraday where Yahoo provides it (note: intraday historical coverage is limited on Yahoo; use intraday only for recent windows).
  - Save data to parquet/CSV, provide a CLI, add unit tests, and example notebook.
- Acceptance criteria:
  - `src/data/yfinance_downloader.py`, `scripts/fetch_historical.py`, `notebooks/ADTN_historical.ipynb`, and tests added.
  - Downloader produces `data/<symbol>.parquet`.


3) Evaluate Tradier as alternative options data & API

- Priority: P1
- Size: S
- Labels: data, backend, P1, size/S
- Assignee: @evansh
- Description:
  - Investigate Tradier dev account onboarding, endpoints for option chains/historical option prices, auth, rate limits, and cost.
  - Compare Tradier to TD Ameritrade and paid vendors (Polygon/Tiingo) and recommend path for MVP vs future.
  - Output: `docs/integrations/tradier.md` with comparison and recommendation.
- Acceptance criteria:
  - `docs/integrations/tradier.md` added with a comparison table and recommendation.


4) Build Yahoo-only simulation/backtester for ADTN (intraday where available)

- Priority: P0
- Size: M
- Labels: data, backend, P0, size/M
- Assignee: @evansh
- Description:
  - Build a simple simulation pipeline using `yfinance` data to run backtests without any brokerage connection.
  - Components:
    - Data downloader (yfinance) with caching
    - Simple backtester supporting daily and recent intraday (where available), fixed-% position sizing, slippage, commission, trade logging, equity curve, and P&L metrics (CAGR, Sharpe, max drawdown)
    - CLI to run a simulation and output `trades.csv`, `metrics.json`, and `equity-curve.png`.
    - Example notebook demonstrating a candlestick-based signal on ADTN.
- Acceptance criteria:
  - `scripts/backtest_yahoo.py`, `src/backtest/simple_backtester.py`, `notebooks/ADTN_backtest_example.ipynb`, and tests added.
  - Running the CLI produces `trades.csv` and `equity-curve.png` for a sample date range.


---

# Notes
- Yahoo intraday data is limited historically. The pipeline will use Yahoo intraday for recent windows and daily full history for long-term analysis.
- TD Ameritrade is the chosen broker for later brokerage integration; Tradier is evaluated as an alternative for options.

