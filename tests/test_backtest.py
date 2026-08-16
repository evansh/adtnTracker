"""Tests for adtnTracker."""

import pytest
import pandas as pd
import numpy as np

from src.data.yfinance_downloader import YFinanceDownloader
from src.backtest.simple_backtester import (
    SimpleBacktester,
    BacktestConfig,
    generate_candlestick_signals,
)


class TestYFinanceDownloader:
    """Tests for YFinanceDownloader."""

    def test_init_creates_cache_dir(self, tmp_path):
        cache_dir = tmp_path / "test_cache"
        downloader = YFinanceDownloader(cache_dir=str(cache_dir))
        assert cache_dir.exists()

    def test_get_cache_path(self):
        downloader = YFinanceDownloader(cache_dir="data")
        path = downloader._get_cache_path("ADTN")
        assert path.name == "ADTN.parquet"
        assert path.parent.name == "data"


class TestBacktestConfig:
    """Tests for BacktestConfig."""

    def test_default_config(self):
        config = BacktestConfig()
        assert config.initial_capital == 100000.0
        assert config.position_size_pct == 0.10
        assert config.commission_per_share == 0.005
        assert config.slippage_pct == 0.001
        assert config.min_trade_size == 1

    def test_custom_config(self):
        config = BacktestConfig(
            initial_capital=50000.0,
            position_size_pct=0.20,
            commission_per_share=0.01,
            slippage_pct=0.002,
        )
        assert config.initial_capital == 50000.0
        assert config.position_size_pct == 0.20
        assert config.commission_per_share == 0.01
        assert config.slippage_pct == 0.002


class TestSimpleBacktester:
    """Tests for SimpleBacktester."""

    def create_sample_data(self, n=100):
        """Create sample OHLCV data for testing."""
        dates = pd.date_range("2024-01-01", periods=n, freq="D")
        np.random.seed(42)
        close = 100 + np.cumsum(np.random.randn(n) * 0.5)
        data = pd.DataFrame({
            "symbol": ["TEST"] * n,
            "timestamp": dates,
            "open": close + np.random.randn(n) * 0.1,
            "high": close + np.abs(np.random.randn(n) * 0.3),
            "low": close - np.abs(np.random.randn(n) * 0.3),
            "close": close,
            "volume": np.random.randint(1000000, 5000000, n),
        })
        return data

    def test_backtester_initialization(self):
        config = BacktestConfig(initial_capital=10000.0)
        backtester = SimpleBacktester(config)
        assert backtester.config.initial_capital == 10000.0

    def test_run_with_flat_signals(self):
        data = self.create_sample_data(50)
        signals = pd.Series(0, index=data.index)
        config = BacktestConfig(initial_capital=10000.0)
        backtester = SimpleBacktester(config)
        metrics = backtester.run(data, signals)
        assert metrics["num_trades"] == 0
        assert metrics["final_equity"] == 10000.0

    def test_run_with_long_signals(self):
        data = self.create_sample_data(50)
        signals = pd.Series(0, index=data.index)
        signals.iloc[10] = 1
        signals.iloc[20] = 0
        config = BacktestConfig(initial_capital=10000.0, position_size_pct=0.1)
        backtester = SimpleBacktester(config)
        metrics = backtester.run(data, signals)
        assert metrics["num_trades"] == 1
        assert len(backtester.trades) == 1

    def test_get_trades_df_empty(self):
        backtester = SimpleBacktester()
        df = backtester.get_trades_df()
        assert df.empty
        assert list(df.columns) == [
            "entry_date", "exit_date", "symbol", "side",
            "entry_price", "exit_price", "shares", "pnl", "return_pct"
        ]

    def test_get_equity_curve_df_empty(self):
        backtester = SimpleBacktester()
        df = backtester.get_equity_curve_df()
        assert df.empty
        assert list(df.columns) == ["timestamp", "equity"]


class TestCandlestickSignals:
    """Tests for candlestick signal generation."""

    def test_generate_signals_returns_series(self):
        data = self.create_sample_data(50)
        signals = generate_candlestick_signals(data)
        assert isinstance(signals, pd.Series)
        assert len(signals) == len(data)
        assert set(signals.unique()).issubset({-1, 0, 1})

    def create_sample_data(self, n=100):
        dates = pd.date_range("2024-01-01", periods=n, freq="D")
        np.random.seed(42)
        close = 100 + np.cumsum(np.random.randn(n) * 0.5)
        return pd.DataFrame({
            "symbol": ["TEST"] * n,
            "timestamp": dates,
            "open": close + np.random.randn(n) * 0.1,
            "high": close + np.abs(np.random.randn(n) * 0.3),
            "low": close - np.abs(np.random.randn(n) * 0.3),
            "close": close,
            "volume": np.random.randint(1000000, 5000000, n),
        })


if __name__ == "__main__":
    pytest.main([__file__, "-v"])