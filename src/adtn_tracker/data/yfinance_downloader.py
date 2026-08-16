"""Yahoo Finance data downloader for ADTN equity historicals."""

import logging
from pathlib import Path

import pandas as pd
import yfinance as yf

logger = logging.getLogger(__name__)


class YFinanceDownloader:
    """Download and cache equity historical data from Yahoo Finance."""

    def __init__(self, cache_dir: str = "data"):
        self.cache_dir = Path(cache_dir)
        self.cache_dir.mkdir(parents=True, exist_ok=True)

    def _get_cache_path(self, symbol: str) -> Path:
        return self.cache_dir / f"{symbol.upper()}.parquet"

    def download(
        self,
        symbol: str,
        period: str = "max",
        interval: str = "1d",
        use_cache: bool = True,
    ) -> pd.DataFrame:
        """Download historical data for a symbol.

        Args:
            symbol: Ticker symbol (e.g., 'ADTN')
            period: Period to download ('1d', '5d', '1mo', '3mo', '6mo', '1y', '2y', '5y', '10y', 'ytd', 'max')
            interval: Data interval ('1m', '2m', '5m', '15m', '30m', '60m', '90m', '1h', '1d', '5d', '1wk', '1mo', '3mo')
            use_cache: Whether to use cached data if available

        Returns:
            DataFrame with OHLCV data
        """
        cache_path = self._get_cache_path(symbol)

        if use_cache and cache_path.exists():
            logger.info(f"Loading cached data for {symbol} from {cache_path}")
            return pd.read_parquet(cache_path)

        logger.info(
            f"Downloading {symbol} from Yahoo Finance (period={period}, interval={interval})"
        )
        ticker = yf.Ticker(symbol)
        df = ticker.history(period=period, interval=interval, auto_adjust=True)

        if df.empty:
            raise ValueError(f"No data returned for {symbol}")

        df = df.reset_index()
        df.columns = [c.lower().replace(" ", "_") for c in df.columns]

        if "datetime" in df.columns:
            df = df.rename(columns={"datetime": "timestamp"})
        elif "date" in df.columns:
            df = df.rename(columns={"date": "timestamp"})

        df["symbol"] = symbol.upper()
        df = df[["symbol", "timestamp", "open", "high", "low", "close", "volume"]]
        df = df.dropna()

        logger.info(f"Downloaded {len(df)} rows for {symbol}")
        df.to_parquet(cache_path, index=False)
        logger.info(f"Cached to {cache_path}")

        return df

    def download_intraday_recent(self, symbol: str, days: int = 30) -> pd.DataFrame:
        """Download recent intraday data (limited availability on Yahoo).

        Note: Yahoo only provides intraday data for the last ~30 days for 1m interval,
        and ~60 days for 5m, 15m, 30m, 60m intervals.
        """
        return self.download(symbol, period=f"{days}d", interval="1h", use_cache=False)

    def download_daily_full(self, symbol: str) -> pd.DataFrame:
        """Download full daily history."""
        return self.download(symbol, period="max", interval="1d")


def main():
    import argparse

    parser = argparse.ArgumentParser(description="Download ADTN historical data")
    parser.add_argument("--symbol", default="ADTN", help="Ticker symbol")
    parser.add_argument("--period", default="max", help="Period (e.g., max, 1y, 5y)")
    parser.add_argument("--interval", default="1d", help="Interval (e.g., 1d, 1h, 5m)")
    parser.add_argument("--no-cache", action="store_true", help="Force fresh download")
    parser.add_argument("--cache-dir", default="data", help="Cache directory")

    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO)

    downloader = YFinanceDownloader(cache_dir=args.cache_dir)
    df = downloader.download(
        symbol=args.symbol,
        period=args.period,
        interval=args.interval,
        use_cache=not args.no_cache,
    )
    print(f"Downloaded {len(df)} rows for {args.symbol}")
    print(df.head())
    print(df.tail())


if __name__ == "__main__":
    main()
