#!/usr/bin/env python3
"""CLI script to run backtests on Yahoo Finance data."""

import argparse
import json
import logging
import sys
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd

from src.data.yfinance_downloader import YFinanceDownloader
from src.backtest.simple_backtester import (
    SimpleBacktester,
    BacktestConfig,
    generate_candlestick_signals,
)

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


def main():
    parser = argparse.ArgumentParser(
        description="Run backtest on Yahoo Finance equity data"
    )
    parser.add_argument(
        "--symbol", default="ADTN", help="Ticker symbol (default: ADTN)"
    )
    parser.add_argument(
        "--start-date", help="Start date (YYYY-MM-DD)"
    )
    parser.add_argument(
        "--end-date", help="End date (YYYY-MM-DD)"
    )
    parser.add_argument(
        "--period", default="2y", help="Period to fetch (default: 2y)"
    )
    parser.add_argument(
        "--interval", default="1d", help="Data interval (default: 1d)"
    )
    parser.add_argument(
        "--capital", type=float, default=100000.0, help="Initial capital (default: 100000)"
    )
    parser.add_argument(
        "--position-size", type=float, default=0.10, help="Position size as fraction of capital (default: 0.10)"
    )
    parser.add_argument(
        "--commission", type=float, default=0.005, help="Commission per share (default: 0.005)"
    )
    parser.add_argument(
        "--slippage", type=float, default=0.001, help="Slippage as fraction (default: 0.001)"
    )
    parser.add_argument(
        "--cache-dir", default="data", help="Cache directory (default: data)"
    )
    parser.add_argument(
        "--output-dir", default="output", help="Output directory for results (default: output)"
    )
    parser.add_argument(
        "--no-cache", action="store_true", help="Force fresh download"
    )
    parser.add_argument(
        "--intraday", action="store_true", help="Use intraday data (recent only)"
    )

    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    downloader = YFinanceDownloader(cache_dir=args.cache_dir)

    try:
        if args.intraday:
            logger.info(f"Fetching recent intraday data for {args.symbol}")
            df = downloader.download_intraday_recent(args.symbol)
        else:
            logger.info(f"Fetching {args.period} {args.interval} data for {args.symbol}")
            df = downloader.download(
                symbol=args.symbol,
                period=args.period,
                interval=args.interval,
                use_cache=not args.no_cache,
            )

        if args.start_date:
            df = df[df["timestamp"] >= args.start_date]
        if args.end_date:
            df = df[df["timestamp"] <= args.end_date]

        logger.info(f"Data range: {df['timestamp'].min()} to {df['timestamp'].max()}, {len(df)} rows")

        signals = generate_candlestick_signals(df)

        config = BacktestConfig(
            initial_capital=args.capital,
            position_size_pct=args.position_size,
            commission_per_share=args.commission,
            slippage_pct=args.slippage,
        )

        backtester = SimpleBacktester(config)
        metrics = backtester.run(df, signals)

        trades_df = backtester.get_trades_df()
        equity_df = backtester.get_equity_curve_df()

        trades_path = output_dir / "trades.csv"
        trades_df.to_csv(trades_path, index=False)
        logger.info(f"Saved {len(trades_df)} trades to {trades_path}")

        metrics_path = output_dir / "metrics.json"
        with open(metrics_path, "w") as f:
            json.dump(metrics, f, indent=2, default=str)
        logger.info(f"Saved metrics to {metrics_path}")

        equity_path = output_dir / "equity-curve.png"
        plot_equity_curve(equity_df, df, trades_df, equity_path)
        logger.info(f"Saved equity curve plot to {equity_path}")

        print("\n=== BACKTEST RESULTS ===")
        print(f"Symbol: {args.symbol}")
        print(f"Period: {args.period} ({args.interval})")
        print(f"Initial Capital: ${args.capital:,.2f}")
        print(f"Final Equity: ${metrics.get('final_equity', 0):,.2f}")
        print(f"Total Return: {metrics.get('total_return', 0):.2%}")
        print(f"CAGR: {metrics.get('cagr', 0):.2%}")
        print(f"Sharpe Ratio: {metrics.get('sharpe', 0):.2f}")
        print(f"Max Drawdown: {metrics.get('max_drawdown', 0):.2%}")
        print(f"Win Rate: {metrics.get('win_rate', 0):.2%}")
        print(f"Profit Factor: {metrics.get('profit_factor', 0):.2f}")
        print(f"Number of Trades: {metrics.get('num_trades', 0)}")

    except Exception as e:
        logger.error(f"Backtest failed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


def plot_equity_curve(equity_df: pd.DataFrame, price_df: pd.DataFrame, trades_df: pd.DataFrame, output_path: Path):
    """Plot equity curve with price and trade markers."""
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 8), gridspec_kw={"height_ratios": [2, 1]}, sharex=True)

    ax1.plot(equity_df["timestamp"], equity_df["equity"], label="Equity Curve", color="blue", linewidth=1.5)
    ax1.set_ylabel("Equity ($)")
    ax1.set_title(f"Backtest Equity Curve - {price_df['symbol'].iloc[0]}")
    ax1.legend()
    ax1.grid(True, alpha=0.3)

    ax2.plot(price_df["timestamp"], price_df["close"], label="Close Price", color="black", linewidth=0.8, alpha=0.7)

    if not trades_df.empty:
        longs = trades_df[trades_df["side"] == "long"]
        shorts = trades_df[trades_df["side"] == "short"]
        if not longs.empty:
            ax2.scatter(longs["entry_date"], longs["entry_price"], marker="^", color="green", s=50, label="Long Entry", zorder=5)
            ax2.scatter(longs["exit_date"], longs["exit_price"], marker="v", color="red", s=50, label="Long Exit", zorder=5)
        if not shorts.empty:
            ax2.scatter(shorts["entry_date"], shorts["entry_price"], marker="v", color="red", s=50, label="Short Entry", zorder=5)
            ax2.scatter(shorts["exit_date"], shorts["exit_price"], marker="^", color="green", s=50, label="Short Exit", zorder=5)

    ax2.set_ylabel("Price ($)")
    ax2.set_xlabel("Date")
    ax2.legend()
    ax2.grid(True, alpha=0.3)

    plt.tight_layout()
    plt.savefig(output_path, dpi=150)
    plt.close()


if __name__ == "__main__":
    main()