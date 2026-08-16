"""Unit tests for backtester."""

import numpy as np
import pandas as pd

from adtn_tracker.backtest import (
    BacktestConfig,
    SimpleBacktester,
    generate_candlestick_signals,
    generate_sma_crossover_signals,
)


class TestBacktestConfig:
    """Tests for BacktestConfig."""

    def test_defaults(self):
        config = BacktestConfig()
        assert config.initial_capital == 100000.0
        assert config.position_size_pct == 0.10
        assert config.commission_per_share == 0.005
        assert config.slippage_pct == 0.001
        assert config.min_trade_size == 1

    def test_custom(self):
        config = BacktestConfig(
            initial_capital=50000.0,
            position_size_pct=0.20,
            commission_per_share=0.01,
            slippage_pct=0.002,
        )
        assert config.initial_capital == 50000.0
        assert config.position_size_pct == 0.20


class TestSimpleBacktester:
    """Tests for SimpleBacktester."""

    def create_sample_data(self, n: int = 100, trend: float = 0.0) -> pd.DataFrame:
        """Create sample OHLCV data."""
        dates = pd.date_range("2024-01-01", periods=n, freq="D")
        np.random.seed(42)
        returns = np.random.randn(n) * 0.02 + trend
        close = 100 * np.exp(np.cumsum(returns))

        return pd.DataFrame(
            {
                "symbol": ["TEST"] * n,
                "timestamp": dates,
                "open": close * (1 + np.random.randn(n) * 0.001),
                "high": close * (1 + np.abs(np.random.randn(n)) * 0.01),
                "low": close * (1 - np.abs(np.random.randn(n)) * 0.01),
                "close": close,
                "volume": np.random.randint(1000000, 5000000, n),
            }
        )

    def test_initialization(self):
        config = BacktestConfig(initial_capital=10000.0)
        backtester = SimpleBacktester(config)
        assert backtester.config.initial_capital == 10000.0

    def test_flat_signals_no_trades(self):
        data = self.create_sample_data(50)
        signals = pd.Series(0, index=data.index)

        backtester = SimpleBacktester(BacktestConfig(initial_capital=10000.0))
        metrics = backtester.run(data, signals)

        assert metrics["num_trades"] == 0
        assert metrics["final_equity"] == 10000.0
        assert len(backtester.trades) == 0

    def test_single_long_trade(self):
        data = self.create_sample_data(50, trend=0.02)  # Stronger uptrend
        signals = pd.Series(0, index=data.index)
        signals.iloc[10] = 1  # Enter long
        signals.iloc[30] = 0  # Exit

        config = BacktestConfig(
            initial_capital=10000.0,
            position_size_pct=0.1,
            commission_per_share=0.0,
            slippage_pct=0.0,
        )
        backtester = SimpleBacktester(config)
        metrics = backtester.run(data, signals)

        assert metrics["num_trades"] == 1
        assert len(backtester.trades) == 1
        trade = backtester.trades[0]
        assert trade.side == "long"
        # With zero costs and uptrend, should profit
        assert trade.pnl > 0

    def test_single_short_trade(self):
        # Create deterministic downtrend data
        dates = pd.date_range("2024-01-01", periods=50, freq="D")
        close = 100 - np.arange(50) * 0.5  # Steady decline

        data = pd.DataFrame(
            {
                "symbol": ["TEST"] * 50,
                "timestamp": dates,
                "open": close,
                "high": close + 0.5,
                "low": close - 0.5,
                "close": close,
                "volume": [1000000] * 50,
            }
        )
        signals = pd.Series(0, index=data.index)
        signals.iloc[10] = -1  # Enter short
        signals.iloc[30] = 0  # Exit

        config = BacktestConfig(
            initial_capital=10000.0,
            position_size_pct=0.1,
            commission_per_share=0.0,
            slippage_pct=0.0,
        )
        backtester = SimpleBacktester(config)
        metrics = backtester.run(data, signals)

        assert metrics["num_trades"] == 1
        trade = backtester.trades[0]
        assert trade.side == "short"
        # With zero costs and steady downtrend, short should profit
        assert trade.pnl > 0

    def test_multiple_trades(self):
        data = self.create_sample_data(100)
        signals = pd.Series(0, index=data.index)
        signals.iloc[10] = 1
        signals.iloc[20] = 0
        signals.iloc[40] = -1
        signals.iloc[60] = 0
        signals.iloc[80] = 1
        signals.iloc[90] = 0

        backtester = SimpleBacktester(BacktestConfig(initial_capital=10000.0))
        metrics = backtester.run(data, signals)

        assert metrics["num_trades"] == 3

    def test_commission_and_slippage_reduce_returns(self):
        data = self.create_sample_data(50, trend=0.01)
        signals = pd.Series(0, index=data.index)
        signals.iloc[10] = 1
        signals.iloc[30] = 0

        # High costs
        config_high = BacktestConfig(
            initial_capital=10000.0,
            position_size_pct=0.1,
            commission_per_share=0.10,
            slippage_pct=0.01,
        )
        # Low costs
        config_low = BacktestConfig(
            initial_capital=10000.0,
            position_size_pct=0.1,
            commission_per_share=0.001,
            slippage_pct=0.0001,
        )

        backtester_high = SimpleBacktester(config_high)
        metrics_high = backtester_high.run(data, signals)

        backtester_low = SimpleBacktester(config_low)
        metrics_low = backtester_low.run(data, signals)

        # High costs should reduce returns
        assert metrics_high["total_return"] < metrics_low["total_return"]

    def test_get_trades_df(self):
        backtester = SimpleBacktester()
        df = backtester.get_trades_df()
        assert df.empty
        expected_cols = [
            "entry_date",
            "exit_date",
            "symbol",
            "side",
            "entry_price",
            "exit_price",
            "shares",
            "pnl",
            "return_pct",
        ]
        assert list(df.columns) == expected_cols

    def test_get_equity_curve_df(self):
        backtester = SimpleBacktester()
        df = backtester.get_equity_curve_df()
        assert df.empty
        assert list(df.columns) == ["timestamp", "equity"]


class TestCandlestickSignals:
    """Tests for candlestick signal generation."""

    def create_ohlc_data(self) -> pd.DataFrame:
        """Create data with known patterns."""
        dates = pd.date_range("2024-01-01", periods=20, freq="D")

        # Create specific patterns
        data = {
            "symbol": ["TEST"] * 20,
            "timestamp": dates,
            "open": [
                100,
                102,
                101,
                99,
                103,
                105,
                104,
                106,
                108,
                107,
                109,
                111,
                110,
                112,
                114,
                113,
                115,
                117,
                116,
                118,
            ],
            "high": [
                103,
                104,
                103,
                102,
                106,
                108,
                107,
                109,
                111,
                110,
                112,
                114,
                113,
                115,
                117,
                116,
                118,
                120,
                119,
                121,
            ],
            "low": [
                99,
                100,
                99,
                97,
                101,
                103,
                102,
                104,
                106,
                105,
                107,
                109,
                108,
                110,
                112,
                111,
                113,
                115,
                114,
                116,
            ],
            "close": [
                102,
                101,
                103,
                105,
                104,
                106,
                108,
                107,
                109,
                111,
                110,
                112,
                114,
                113,
                115,
                117,
                116,
                118,
                120,
                119,
            ],
            "volume": [1000000] * 20,
        }
        return pd.DataFrame(data)

    def test_generate_signals_returns_series(self):
        data = self.create_ohlc_data()
        signals = generate_candlestick_signals(data)

        assert isinstance(signals, pd.Series)
        assert len(signals) == len(data)
        assert set(signals.unique()).issubset({-1, 0, 1})

    def test_bullish_engulfing_detected(self):
        # Create clear bullish engulfing: prev day bearish, current day bullish and engulfs
        data = pd.DataFrame(
            {
                "symbol": ["TEST"] * 5,
                "timestamp": pd.date_range("2024-01-01", periods=5, freq="D"),
                "open": [100, 105, 104, 100, 103],
                "high": [103, 106, 105, 108, 106],
                "low": [99, 103, 102, 99, 101],
                "close": [
                    102,
                    103,
                    102,
                    107,
                    104,
                ],  # Day 3 (idx 2): bearish; Day 4 (idx 3): bullish engulfing
                "volume": [1000000] * 5,
            }
        )
        # Day 2: open=104, close=102 (bearish, body=-2)
        # Day 3: open=100, close=107 (bullish, body=7)
        # Check: open[3]=100 < close[2]=102 ✓, close[3]=107 > open[2]=104 ✓

        signals = generate_candlestick_signals(data)
        # Should detect bullish engulfing on day 4 (index 3)
        assert signals.iloc[3] == 1

    def test_bearish_engulfing_detected(self):
        # Create clear bearish engulfing: prev day bullish, current day bearish and engulfs
        data = pd.DataFrame(
            {
                "symbol": ["TEST"] * 5,
                "timestamp": pd.date_range("2024-01-01", periods=5, freq="D"),
                "open": [100, 100, 102, 108, 103],
                "high": [103, 103, 105, 110, 106],
                "low": [99, 99, 101, 101, 101],
                "close": [
                    102,
                    102,
                    104,
                    101,
                    104,
                ],  # Day 3 (idx 2): bullish; Day 4 (idx 3): bearish engulfing
                "volume": [1000000] * 5,
            }
        )
        # Day 2: open=102, close=104 (bullish, body=2)
        # Day 3: open=108, close=101 (bearish, body=-7)
        # Check: open[3]=108 > close[2]=104 ✓, close[3]=101 < open[2]=102 ✓

        signals = generate_candlestick_signals(data)
        assert signals.iloc[3] == -1


class TestSMACrossoverSignals:
    """Tests for SMA crossover signals."""

    def test_golden_cross(self):
        # Create data with clear golden cross
        # First 15 days flat, then sharp rise
        close_prices = [100] * 15 + list(range(100, 180))  # 15 flat + 80 rising = 95
        dates = pd.date_range("2024-01-01", periods=len(close_prices), freq="D")
        data = pd.DataFrame(
            {
                "symbol": ["TEST"] * len(close_prices),
                "timestamp": dates,
                "open": close_prices,
                "high": [c + 1 for c in close_prices],
                "low": [c - 1 for c in close_prices],
                "close": close_prices,
                "volume": [1000000] * len(close_prices),
            }
        )

        signals = generate_sma_crossover_signals(data, fast=5, slow=10)
        # Should have golden crosses during the rise
        assert (signals == 1).any()

    def test_death_cross(self):
        # Create data with clear death cross
        # First 15 days flat, then sharp fall
        close_prices = [180] * 15 + list(range(180, 100, -1))  # 15 flat + 80 falling = 95
        dates = pd.date_range("2024-01-01", periods=len(close_prices), freq="D")
        data = pd.DataFrame(
            {
                "symbol": ["TEST"] * len(close_prices),
                "timestamp": dates,
                "open": close_prices,
                "high": [c + 1 for c in close_prices],
                "low": [c - 1 for c in close_prices],
                "close": close_prices,
                "volume": [1000000] * len(close_prices),
            }
        )

        signals = generate_sma_crossover_signals(data, fast=5, slow=10)
        # Should have death crosses during the fall
        assert (signals == -1).any()
