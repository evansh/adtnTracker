# adtnTracker

StockBot for tracking and trading Adtran (ADTN)

## Structure
```
adtnTracker/
├── src/
│   ├── data/
│   │   ├── __init__.py
│   │   └── yfinance_downloader.py    # Yahoo Finance data downloader
│   └── backtest/
│       ├── __init__.py
│       └── simple_backtester.py      # Vectorized backtester
├── scripts/
│   ├── fetch_historical.py           # CLI: fetch equity data
│   └── backtest_yahoo.py             # CLI: run backtests
├── notebooks/
│   ├── ADTN_historical.ipynb         # Data exploration notebook
│   └── ADTN_backtest_example.ipynb   # Backtest demonstration
├── docs/
│   └── integrations/
│       ├── td_ameritrade.md          # TD Ameritrade/Schwab integration guide
│       └── tradier.md                # Tradier API evaluation
├── tests/
│   └── test_backtest.py              # Unit tests
├── data/                             # Cached parquet files (gitignored)
├── output/                           # Backtest outputs (gitignored)
├── requirements.txt
└── README.md
```

## Quick Start

### Install Dependencies
```bash
pip install -r requirements.txt
```

### Fetch Historical Data
```bash
# Daily data (full history)
python scripts/fetch_historical.py --symbol ADTN --period max --interval 1d

# Recent intraday (hourly, last 30 days)
python scripts/fetch_historical.py --symbol ADTN --intraday-recent
```

### Run Backtest
```bash
# Daily backtest (2 years)
python scripts/backtest_yahoo.py --symbol ADTN --period 2y --interval 1d --output-dir output

# Intraday backtest (recent)
python scripts/backtest_yahoo.py --symbol ADTN --intraday --output-dir output_intraday
```

Outputs:
- `output/trades.csv` - All completed trades
- `output/metrics.json` - Performance metrics
- `output/equity-curve.png` - Equity curve chart

### Run Tests
```bash
PYTHONPATH=. python -m pytest tests/ -v
```

## Backtest Results (ADTN, 2Y Daily, Candlestick Patterns)
```
Total Return: -1.14%
CAGR: -1.15%
Sharpe Ratio: -0.46
Max Drawdown: -2.67%
Win Rate: 50.00%
Profit Factor: 0.75
Number of Trades: 28
```

## Documentation
- [TD Ameritrade/Schwab Integration](docs/integrations/td_ameritrade.md)
- [Tradier API Evaluation](docs/integrations/tradier.md)

## Notebooks
- [ADTN Historical Analysis](notebooks/ADTN_historical.ipynb)
- [ADTN Backtest Example](notebooks/ADTN_backtest_example.ipynb)

## Roadmap (from Backlog)
- [x] #3: Integrate yfinance for equity historicals
- [x] #5: Build Yahoo-only simulation/backtester for ADTN
- [ ] #1: Evaluate TD Ameritrade developer access & onboarding (docs done)
- [ ] #4: Evaluate Tradier as alternative options data & API (docs done)