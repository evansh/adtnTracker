"""Yahoo Finance data provider implementation."""

import logging
import time
from datetime import datetime, timedelta
from pathlib import Path

import pandas as pd
import yfinance as yf

from adtn_tracker.config import YFinanceConfig, get_settings
from adtn_tracker.core import (
    AssetClass,
    Bar,
    DataProvider,
    OptionContract,
    OptionQuote,
    Quote,
    Symbol,
    TimeFrame,
)

logger = logging.getLogger(__name__)


class YFinanceProvider(DataProvider):
    """Yahoo Finance data provider with caching."""

    _TIMEFRAME_MAP = {
        TimeFrame.MINUTE_1: "1m",
        TimeFrame.MINUTE_5: "5m",
        TimeFrame.MINUTE_15: "15m",
        TimeFrame.MINUTE_30: "30m",
        TimeFrame.HOUR_1: "1h",
        TimeFrame.DAY_1: "1d",
        TimeFrame.WEEK_1: "1wk",
        TimeFrame.MONTH_1: "1mo",
    }

    _PERIOD_MAP = {
        TimeFrame.MINUTE_1: "7d",
        TimeFrame.MINUTE_5: "60d",
        TimeFrame.MINUTE_15: "60d",
        TimeFrame.MINUTE_30: "60d",
        TimeFrame.HOUR_1: "730d",
        TimeFrame.DAY_1: "max",
        TimeFrame.WEEK_1: "max",
        TimeFrame.MONTH_1: "max",
    }

    def __init__(self, config: YFinanceConfig | None = None):
        self._config = config or get_settings().yfinance
        self._cache_dir = Path(self._config.cache_dir)
        self._cache_dir.mkdir(parents=True, exist_ok=True)
        self._tickers: dict[str, yf.Ticker] = {}
        self._connected = False

    def connect(self) -> None:
        """Establish connection (no-op for yfinance)."""
        self._connected = True
        logger.info("YFinance provider connected")

    def disconnect(self) -> None:
        """Close connection."""
        self._tickers.clear()
        self._connected = False
        logger.info("YFinance provider disconnected")

    def is_connected(self) -> bool:
        return self._connected

    def _get_ticker(self, symbol: Symbol) -> yf.Ticker:
        key = str(symbol)
        if key not in self._tickers:
            self._tickers[key] = yf.Ticker(key)
        return self._tickers[key]

    def _get_cache_path(self, symbol: Symbol, timeframe: TimeFrame) -> Path:
        return self._cache_dir / f"{symbol.ticker}_{timeframe.value}.parquet"

    def _download_with_retry(
        self,
        ticker: yf.Ticker,
        interval: str,
        period: str | None = None,
        start: datetime | None = None,
        end: datetime | None = None,
    ) -> pd.DataFrame:
        """Download with exponential backoff retry."""
        max_retries = self._config.max_retries
        base_delay = 1

        for attempt in range(max_retries):
            try:
                if start and end:
                    df = ticker.history(
                        start=start.strftime("%Y-%m-%d"),
                        end=end.strftime("%Y-%m-%d"),
                        interval=interval,
                        auto_adjust=True,
                    )
                else:
                    df = ticker.history(
                        period=period,
                        interval=interval,
                        auto_adjust=True,
                    )
                return df
            except Exception as e:
                if attempt == max_retries - 1:
                    raise
                wait = base_delay * (2**attempt)
                logger.warning(
                    f"Download failed (attempt {attempt + 1}/{max_retries}): {e}. Retrying in {wait}s..."
                )
                time.sleep(wait)
        return pd.DataFrame()

    def _df_to_bars(self, df: pd.DataFrame, symbol: Symbol) -> list[Bar]:
        if df.empty:
            return []

        df = df.reset_index()
        df.columns = [c.lower().replace(" ", "_") for c in df.columns]

        timestamp_col = "datetime" if "datetime" in df.columns else "date"
        df = df.rename(columns={timestamp_col: "timestamp"})

        bars = []
        for _, row in df.iterrows():
            bars.append(
                Bar(
                    symbol=symbol,
                    timestamp=pd.Timestamp(row["timestamp"]).to_pydatetime(),
                    open=float(row["open"]),
                    high=float(row["high"]),
                    low=float(row["low"]),
                    close=float(row["close"]),
                    volume=int(row["volume"]),
                    vwap=float(row.get("vwap", row["close"])) if "vwap" in row else None,
                    raw=row.to_dict(),
                )
            )
        return bars

    def get_bars(
        self,
        symbol: Symbol,
        timeframe: TimeFrame,
        start: datetime,
        end: datetime | None = None,
        limit: int | None = None,
    ) -> list[Bar]:
        yf_interval = self._TIMEFRAME_MAP[timeframe]
        yf_period = self._PERIOD_MAP[timeframe]

        cache_path = self._get_cache_path(symbol, timeframe)

        # Try cache first for daily data
        if timeframe >= TimeFrame.DAY_1 and cache_path.exists() and not end:
            try:
                cached = pd.read_parquet(cache_path)
                cached = cached[cached["timestamp"] >= start]
                if limit:
                    cached = cached.tail(limit)
                return self._df_to_bars(cached, symbol)
            except Exception as e:
                logger.warning(f"Cache read failed: {e}")

        ticker = self._get_ticker(symbol)

        if end is None:
            end = datetime.now()

        # For intraday, yfinance requires period not start/end
        if timeframe < TimeFrame.DAY_1:
            df = self._download_with_retry(ticker, interval=yf_interval, period=yf_period)
            df = df[df.index >= start]
        else:
            df = self._download_with_retry(ticker, interval=yf_interval, start=start, end=end)

        if limit:
            df = df.tail(limit)

        bars = self._df_to_bars(df, symbol)

        # Update cache for daily data
        if timeframe >= TimeFrame.DAY_1 and not df.empty:
            try:
                existing = pd.DataFrame()
                if cache_path.exists():
                    existing = pd.read_parquet(cache_path)
                combined = (
                    pd.concat([existing, df])
                    .drop_duplicates(subset=["timestamp"])
                    .sort_values("timestamp")
                )
                combined.to_parquet(cache_path, index=False)
            except Exception as e:
                logger.warning(f"Cache write failed: {e}")

        return bars

    def get_latest_bar(self, symbol: Symbol, timeframe: TimeFrame) -> Bar | None:
        bars = self.get_bars(symbol, timeframe, datetime.now() - timedelta(days=5), limit=1)
        return bars[0] if bars else None

    def get_quote(self, symbol: Symbol) -> Quote:
        ticker = self._get_ticker(symbol)
        info = ticker.info

        return Quote(
            symbol=symbol,
            bid=info.get("bid", 0.0),
            ask=info.get("ask", 0.0),
            bid_size=info.get("bidSize", 0),
            ask_size=info.get("askSize", 0),
            last=info.get("regularMarketPrice", info.get("currentPrice", 0.0)),
            timestamp=datetime.now(),
            raw=info,
        )

    def get_option_chain(
        self,
        underlying: Symbol,
        expiration: datetime | None = None,
    ) -> list[OptionContract]:
        ticker = self._get_ticker(underlying)

        try:
            expirations = ticker.options
            if not expirations:
                return []

            if expiration:
                expirations = [
                    e
                    for e in expirations
                    if datetime.strptime(e, "%Y-%m-%d").date() >= expiration.date()
                ]
                if not expirations:
                    return []
                expirations = [expirations[0]]  # Nearest

            contracts = []
            for exp_str in expirations:
                exp_date = datetime.strptime(exp_str, "%Y-%m-%d")
                chain = ticker.option_chain(exp_str)

                for _, row in chain.calls.iterrows():
                    contracts.append(
                        OptionContract(
                            symbol=Symbol(
                                ticker=row["contractSymbol"], asset_class=AssetClass.OPTION
                            ),
                            underlying=underlying,
                            strike=float(row["strike"]),
                            expiration=exp_date,
                            option_type="call",
                        )
                    )

                for _, row in chain.puts.iterrows():
                    contracts.append(
                        OptionContract(
                            symbol=Symbol(
                                ticker=row["contractSymbol"], asset_class=AssetClass.OPTION
                            ),
                            underlying=underlying,
                            strike=float(row["strike"]),
                            expiration=exp_date,
                            option_type="put",
                        )
                    )

            return contracts
        except Exception as e:
            logger.error(f"Failed to get option chain: {e}")
            return []

    def get_option_quote(self, contract: OptionContract) -> OptionQuote:
        ticker = self._get_ticker(contract.underlying)
        exp_str = contract.expiration.strftime("%Y-%m-%d")

        try:
            chain = ticker.option_chain(exp_str)

            if contract.option_type == "call":
                df = chain.calls
            else:
                df = chain.puts

            row = df[df["contractSymbol"] == contract.symbol.ticker]
            if row.empty:
                raise ValueError(f"Contract not found: {contract.symbol}")

            row = row.iloc[0]

            return OptionQuote(
                contract=contract,
                bid=float(row.get("bid", 0)),
                ask=float(row.get("ask", 0)),
                last=float(row.get("lastPrice", 0)),
                volume=int(row.get("volume", 0)),
                open_interest=int(row.get("openInterest", 0)),
                implied_volatility=float(row.get("impliedVolatility", 0))
                if "impliedVolatility" in row
                else None,
                delta=None,  # yfinance doesn't provide Greeks
                gamma=None,
                theta=None,
                vega=None,
                rho=None,
                timestamp=datetime.now(),
                raw=row.to_dict(),
            )
        except Exception as e:
            logger.error(f"Failed to get option quote: {e}")
            return OptionQuote(
                contract=contract,
                bid=0,
                ask=0,
                last=0,
                volume=0,
                open_interest=0,
                timestamp=datetime.now(),
            )

    def subscribe_bars(self, symbols: list[Symbol], timeframe: TimeFrame, callback) -> None:
        raise NotImplementedError("YFinance doesn't support real-time streaming")

    def unsubscribe_bars(self, symbols: list[Symbol]) -> None:
        pass
