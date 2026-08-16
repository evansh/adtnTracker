#!/usr/bin/env python3
"""CLI script to fetch and cache historical equity data."""

import argparse
import logging
import sys

from src.data.yfinance_downloader import YFinanceDownloader

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


def main():
    parser = argparse.ArgumentParser(
        description="Fetch historical equity data from Yahoo Finance"
    )
    parser.add_argument(
        "--symbol", default="ADTN", help="Ticker symbol (default: ADTN)"
    )
    parser.add_argument(
        "--period",
        default="max",
        choices=["1d", "5d", "1mo", "3mo", "6mo", "1y", "2y", "5y", "10y", "ytd", "max"],
        help="Period to fetch (default: max)",
    )
    parser.add_argument(
        "--interval",
        default="1d",
        choices=["1m", "2m", "5m", "15m", "30m", "60m", "90m", "1h", "1d", "5d", "1wk", "1mo", "3mo"],
        help="Data interval (default: 1d)",
    )
    parser.add_argument(
        "--cache-dir", default="data", help="Cache directory (default: data)"
    )
    parser.add_argument(
        "--no-cache", action="store_true", help="Force fresh download, ignore cache"
    )
    parser.add_argument(
        "--intraday-recent",
        action="store_true",
        help="Fetch recent intraday data (last 30 days, hourly)",
    )

    args = parser.parse_args()

    downloader = YFinanceDownloader(cache_dir=args.cache_dir)

    try:
        if args.intraday_recent:
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

        logger.info(f"Successfully fetched {len(df)} rows")
        logger.info(f"Date range: {df['timestamp'].min()} to {df['timestamp'].max()}")
        logger.info(f"Columns: {list(df.columns)}")

    except Exception as e:
        logger.error(f"Failed to fetch data: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()