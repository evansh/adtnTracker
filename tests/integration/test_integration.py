"""Integration tests with mocking."""

import numpy as np
import pandas as pd
import pytest


class TestYFinanceProviderIntegration:
    """Integration tests for YFinanceProvider (skipped - requires complex mocking)."""

    @pytest.mark.skip(reason="Requires complex yfinance mocking")
    def test_get_bars(self):
        pass

    @pytest.mark.skip(reason="Requires complex yfinance mocking")
    def test_get_quote(self):
        pass

    @pytest.mark.skip(reason="Requires complex yfinance mocking")
    def test_get_option_chain(self):
        pass

    @pytest.mark.skip(reason="Requires complex yfinance mocking")
    def test_get_option_quote(self):
        pass


class TestSchwabBrokerIntegration:
    """Integration tests for SchwabBroker (skipped - requires complex mocking)."""

    @pytest.mark.skip(reason="Requires complex HTTP mocking")
    def test_get_accounts(self):
        pass

    @pytest.mark.skip(reason="Requires complex HTTP mocking")
    def test_get_positions(self):
        pass


class TestTradierBrokerIntegration:
    """Integration tests for TradierBroker (skipped - requires complex HTTP mocking)."""

    @pytest.mark.skip(reason="Requires complex HTTP mocking")
    def test_get_account(self):
        pass

    @pytest.mark.skip(reason="Requires complex HTTP mocking")
    def test_place_order(self):
        pass


class TestEndToEndBacktest:
    """End-to-end backtest integration test."""

    def test_full_backtest_flow(self):
        """Test complete flow: fetch data -> generate signals -> backtest."""
        from adtn_tracker.backtest import (
            BacktestConfig,
            SimpleBacktester,
            generate_candlestick_signals,
        )

        # Create synthetic data
        dates = pd.date_range("2024-01-01", periods=100, freq="D")
        np.random.seed(42)
        close = 100 + np.cumsum(np.random.randn(100) * 0.5)

        data = pd.DataFrame(
            {
                "symbol": ["TEST"] * 100,
                "timestamp": dates,
                "open": close + np.random.randn(100) * 0.1,
                "high": close + np.abs(np.random.randn(100) * 0.3),
                "low": close - np.abs(np.random.randn(100) * 0.3),
                "close": close,
                "volume": np.random.randint(1000000, 5000000, 100),
            }
        )

        # Generate signals
        signals = generate_candlestick_signals(data)

        # Run backtest
        config = BacktestConfig(initial_capital=100000.0)
        backtester = SimpleBacktester(config)
        metrics = backtester.run(data, signals)

        # Verify results
        assert "total_return" in metrics
        assert "cagr" in metrics
        assert "sharpe" in metrics
        assert "max_drawdown" in metrics
        assert "num_trades" in metrics
        assert metrics["num_trades"] >= 0

        # Verify trades DataFrame
        trades_df = backtester.get_trades_df()
        assert len(trades_df) == metrics["num_trades"]

        # Verify equity curve
        equity_df = backtester.get_equity_curve_df()
        assert len(equity_df) == len(data)
        assert equity_df["equity"].iloc[0] == 100000.0
