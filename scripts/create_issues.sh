#!/usr/bin/env bash
# create_issues.sh
# Script to create the initial issues in the repository using the GitHub CLI (gh).
# Requirements: gh (https://cli.github.com/) authenticated with permissions to create issues in evansh/adtnTracker.

set -euo pipefail

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh CLI not found. Install from https://cli.github.com/"
  exit 1
fi

REPO="evansh/adtnTracker"
ASSIGNEE="evansh"
MILESTONE_NAME="MVP"

# Ensure milestone exists (create if missing)
if ! gh milestone view "$MILESTONE_NAME" --repo "$REPO" >/dev/null 2>&1; then
  echo "Creating milestone $MILESTONE_NAME"
  gh milestone create "$MILESTONE_NAME" --repo "$REPO" --description "MVP milestone" || true
fi

create_issue() {
  local title="$1"
  local body="$2"
  local labels="$3"
  echo "Creating issue: $title"
  gh issue create --repo "$REPO" --title "$title" --body "$body" --label "$labels" --assignee "$ASSIGNEE" --milestone "$MILESTONE_NAME"
}

# Issue 1: TD Ameritrade evaluation
create_issue "Evaluate TD Ameritrade developer access & onboarding" $'Verify current TD API status (post-acquisition), OAuth requirements, scopes for options and trading, rate limits, and app registration steps.\n\nOutput: docs/integrations/td_ameritrade.md with setup steps and recommended retry/caching strategy.\n\nAcceptance criteria:\n- docs/integrations/td_ameritrade.md added to repo with concrete setup steps, scopes, and rate-limit notes.' "backend,infra,P0,size/S"

# Issue 2: yfinance integration
create_issue "Integrate yfinance for equity historicals (daily + intraday where available)" $'Implement a downloader module to fetch and cache ADTN OHLCV using yfinance. Support daily full history and intraday where Yahoo provides it (note: intraday historical coverage is limited on Yahoo; use intraday only for recent windows).\n\nAcceptance criteria:\n- src/data/yfinance_downloader.py, scripts/fetch_historical.py, notebooks/ADTN_historical.ipynb, and tests added.\n- Downloader produces data/<symbol>.parquet' "data,backend,P0,size/M"

# Issue 3: Tradier evaluation
create_issue "Evaluate Tradier as alternative options data & API" $'Investigate Tradier dev onboarding, endpoints for option chains/historical option prices, auth, rate limits, and cost. Compare Tradier to TD Ameritrade and paid vendors (Polygon/Tiingo) and recommend path for MVP vs future.\n\nAcceptance criteria:\n- docs/integrations/tradier.md added with a comparison table and recommendation.' "data,backend,P1,size/S"

# Issue 4: Yahoo-only simulation/backtester
create_issue "Build Yahoo-only simulation/backtester for ADTN (intraday where available)" $'Build a simple simulation pipeline using yfinance data to run backtests without any brokerage connection. Components: data downloader (yfinance) with caching, simple backtester supporting daily and recent intraday (where available), fixed-% position sizing, slippage, commission, trade logging, equity curve, and P&L metrics (CAGR, Sharpe, max drawdown). CLI to run simulation and output trades.csv, metrics.json, and equity-curve.png. Example notebook demonstrating a candlestick-based signal on ADTN.\n\nAcceptance criteria:\n- scripts/backtest_yahoo.py, src/backtest/simple_backtester.py, notebooks/ADTN_backtest_example.ipynb, and tests added.\n- Running the CLI produces trades.csv and equity-curve.png for a sample date range.' "data,backend,P0,size/M"

echo "All issues created. Use 'gh issue list --repo $REPO' to view them."
