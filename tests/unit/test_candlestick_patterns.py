"""Unit tests for candlestick patterns."""

import pytest
import pandas as pd
import numpy as np
from datetime import datetime

from adtn_tracker.backtest.candlestick_patterns import (
    prepare_candlestick_data,
    hammer,
    inverted_hammer,
    shooting_star,
    hanging_man,
    doji,
    bullish_engulfing,
    bearish_engulfing,
    bullish_harami,
    bearish_harami,
    morning_star,
    evening_star,
    three_white_soldiers,
    three_black_crows,
    ALL_PATTERNS,
    BULLISH_PATTERNS,
    BEARISH_PATTERNS,
    generate_pattern_signals,
    get_pattern_occurrences,
)


class TestCandlestickDataPrep:
    """Tests for candlestick data preparation."""
    
    def test_prepare_data_creates_expected_columns(self):
        data = pd.DataFrame({
            "timestamp": pd.date_range("2024-01-01", periods=5, freq="D"),
            "open": [100, 102, 101, 103, 105],
            "high": [103, 105, 104, 106, 108],
            "low": [99, 101, 100, 102, 104],
            "close": [102, 101, 103, 105, 104],
            "volume": [1000000] * 5,
        })
        
        df = prepare_candlestick_data(data)
        
        expected_cols = ["body", "body_abs", "range", "upper_wick", "lower_wick", 
                         "is_bullish", "is_bearish", "is_doji"]
        for col in expected_cols:
            assert col in df.columns
    
    def test_bullish_candle_detection(self):
        data = pd.DataFrame({
            "timestamp": pd.date_range("2024-01-01", periods=2, freq="D"),
            "open": [100, 105],
            "high": [103, 108],
            "low": [99, 104],
            "close": [102, 106],  # Both bullish
            "volume": [1000000] * 2,
        })
        
        df = prepare_candlestick_data(data)
        assert df["is_bullish"].iloc[0] == True
        assert df["is_bullish"].iloc[1] == True
        assert df["is_bearish"].iloc[0] == False
    
    def test_bearish_candle_detection(self):
        data = pd.DataFrame({
            "timestamp": pd.date_range("2024-01-01", periods=2, freq="D"),
            "open": [100, 105],
            "high": [103, 108],
            "low": [99, 104],
            "close": [98, 103],  # Both bearish
            "volume": [1000000] * 2,
        })
        
        df = prepare_candlestick_data(data)
        assert df["is_bearish"].iloc[0] == True
        assert df["is_bearish"].iloc[1] == True
        assert df["is_bullish"].iloc[0] == False


class TestSingleCandlePatterns:
    """Tests for single candle patterns."""
    
    def test_hammer_detection(self):
        # Hammer: small body at top, long lower wick
        # open=100, close=101 (small bullish body), high=101, low=95
        data = pd.DataFrame({
            "timestamp": pd.date_range("2024-01-01", periods=2, freq="D"),
            "open": [100, 100],
            "high": [103, 101],
            "low": [95, 95],    # Long lower wick (100-95=5)
            "close": [101, 101], # Small bullish body (101-100=1)
            "volume": [1000000] * 2,
        })
        
        df = prepare_candlestick_data(data)
        signals = hammer(df)
        # Second candle should be hammer
        assert signals.iloc[1] == True
    
    def test_shooting_star_detection(self):
        # Shooting star: small body at bottom, long upper wick
        # open=100, close=99 (small bearish body), high=105, low=99
        data = pd.DataFrame({
            "timestamp": pd.date_range("2024-01-01", periods=2, freq="D"),
            "open": [100, 100],
            "high": [105, 105],   # Long upper wick
            "low": [99, 99],
            "close": [99, 99],   # Small bearish body (99-100=-1)
            "volume": [1000000] * 2,
        })
        
        df = prepare_candlestick_data(data)
        signals = shooting_star(df)
        assert signals.iloc[1] == True
    
    def test_doji_detection(self):
        # Doji: open == close
        data = pd.DataFrame({
            "timestamp": pd.date_range("2024-01-01", periods=2, freq="D"),
            "open": [100, 100],
            "high": [102, 101],
            "low": [98, 99],
            "close": [100, 100],  # Open == close
            "volume": [1000000] * 2,
        })
        
        df = prepare_candlestick_data(data)
        signals = doji(df)
        assert signals.iloc[1] == True
    
    def test_hammer_vs_shooting_star(self):
        # Hammer and shooting star should not both trigger on same candle
        data = pd.DataFrame({
            "timestamp": pd.date_range("2024-01-01", periods=2, freq="D"),
            "open": [100, 100],
            "high": [105, 100],
            "low": [95, 99],
            "close": [101, 100],
            "volume": [1000000] * 2,
        })
        
        df = prepare_candlestick_data(data)
        h = hammer(df)
        ss = shooting_star(df)
        
        # Can't be both hammer and shooting star
        assert not (h.iloc[1] and ss.iloc[1])


class TestTwoCandlePatterns:
    """Tests for two candle patterns."""
    
    def test_bullish_harami(self):
        # Large bearish (Day 0) then small bullish inside (Day 1)
        # Day 0: large bearish, open=105, close=100
        # Day 1: small bullish inside Day 0, open=101, close=102 (open > 100, close < 105)
        data = pd.DataFrame({
            "timestamp": pd.date_range("2024-01-01", periods=3, freq="D"),
            "open": [105, 105, 101],   # Day 2 opens inside Day 0
            "high": [108, 107, 103],
            "low": [100, 100, 100],
            "close": [100, 98, 102],  # Day 1: bearish inside Day 0; Day 2: bullish inside Day 0
            "volume": [1000000] * 3,
        })
        
        df = prepare_candlestick_data(data)
        signals = bullish_harami(df)
        assert signals.iloc[2] == True
    
    def test_bearish_engulfing(self):
        # Bullish then large bearish that engulfs
        data = pd.DataFrame({
            "timestamp": pd.date_range("2024-01-01", periods=3, freq="D"),
            "open": [100, 99, 105],
            "high": [103, 104, 106],
            "low": [99, 98, 98],
            "close": [102, 101, 98],  # Third closes below prev open
            "volume": [1000000] * 3,
        })
        
        df = prepare_candlestick_data(data)
        signals = bearish_engulfing(df)
        assert signals.iloc[2] == True
    
    def test_bullish_harami(self):
        # Day 0: large bearish, open=105, close=100 (bearish)
        # Day 1: small bearish, open=105, close=98 (bearish)
        # Day 2: bullish inside Day 0, open=101, close=102 (inside 100-105)
        data = pd.DataFrame({
            "timestamp": pd.date_range("2024-01-01", periods=3, freq="D"),
            "open": [105, 105, 101],
            "high": [108, 107, 103],
            "low": [100, 100, 100],
            "close": [100, 98, 102],
            "volume": [1000000] * 3,
        })
        
        df = prepare_candlestick_data(data)
        signals = bullish_harami(df)
        assert signals.iloc[2] == True


class TestThreeCandlePatterns:
    """Tests for three candle patterns."""
    
    def test_morning_star(self):
        # Day 0: large bearish, open=110, close=100, midpoint=105
        # Day 1: small body, gap down, open=98, close=99
        # Day 2: large bullish, open=95, close=110 (closes above midpoint 105)
        # Signal should be at index 2 (third candle)
        data = pd.DataFrame({
            "timestamp": pd.date_range("2024-01-01", periods=3, freq="D"),
            "open": [110, 98, 95],
            "high": [112, 99, 112],
            "low": [105, 97, 94],
            "close": [100, 99, 110],  # Day 2 closes at 110 > 105 (midpoint of Day 0)
            "volume": [1000000] * 3,
        })
        
        df = prepare_candlestick_data(data)
        signals = morning_star(df)
        assert signals.iloc[2] == True
    
    def test_evening_star(self):
        # Large bullish, small middle, large bearish
        data = pd.DataFrame({
            "timestamp": pd.date_range("2024-01-01", periods=4, freq="D"),
            "open": [100, 105, 108, 110],
            "high": [105, 108, 109, 112],
            "low": [98, 103, 107, 105],
            "close": [104, 106, 108, 102],  # Third large bearish
            "volume": [1000000] * 4,
        })
        
        df = prepare_candlestick_data(data)
        signals = evening_star(df)
        assert signals.iloc[3] == True
    
    def test_three_white_soldiers(self):
        # Three consecutive bullish
        data = pd.DataFrame({
            "timestamp": pd.date_range("2024-01-01", periods=5, freq="D"),
            "open": [100, 102, 104, 106, 108],
            "high": [103, 105, 107, 109, 111],
            "low": [99, 101, 103, 105, 107],
            "close": [102, 104, 106, 108, 110],
            "volume": [1000000] * 5,
        })
        
        df = prepare_candlestick_data(data)
        signals = three_white_soldiers(df)
        assert signals.iloc[4] == True


class TestPatternRegistry:
    """Tests for pattern registry."""
    
    def test_all_patterns_defined(self):
        assert len(ALL_PATTERNS) > 20
        assert len(BULLISH_PATTERNS) > 5
        assert len(BEARISH_PATTERNS) > 5
    
    def test_pattern_names_unique(self):
        all_names = list(ALL_PATTERNS.keys())
        assert len(all_names) == len(set(all_names))
    
    def test_no_overlap_bullish_bearish(self):
        bullish = set(BULLISH_PATTERNS.keys())
        bearish = set(BEARISH_PATTERNS.keys())
        assert len(bullish & bearish) == 0


class TestGenerateSignals:
    """Tests for generate_pattern_signals function."""
    
    def test_generate_bullish_signals(self):
        data = pd.DataFrame({
            "timestamp": pd.date_range("2024-01-01", periods=10, freq="D"),
            "open": [100, 102, 99, 101, 100, 102, 101, 103, 102, 104],
            "high": [103, 105, 102, 104, 103, 105, 104, 106, 105, 107],
            "low": [99, 100, 97, 99, 98, 100, 99, 101, 100, 102],
            "close": [102, 101, 100, 102, 101, 103, 102, 104, 103, 105],
            "volume": [1000000] * 10,
        })
        
        signals = generate_pattern_signals(data, ["hammer", "bullish_engulfing"], "bullish")
        assert isinstance(signals, pd.Series)
        assert len(signals) == len(data)
        assert set(signals.unique()).issubset({-1, 0, 1})
    
    def test_generate_bearish_signals(self):
        data = pd.DataFrame({
            "timestamp": pd.date_range("2024-01-01", periods=10, freq="D"),
            "open": [110, 108, 109, 107, 108, 106, 107, 105, 106, 104],
            "high": [112, 110, 111, 109, 110, 108, 109, 107, 108, 106],
            "low": [108, 106, 107, 105, 106, 104, 105, 103, 104, 102],
            "close": [108, 109, 107, 108, 106, 107, 105, 106, 104, 103],
            "volume": [1000000] * 10,
        })
        
        signals = generate_pattern_signals(data, ["shooting_star", "bearish_engulfing"], "bearish")
        assert isinstance(signals, pd.Series)
        assert len(signals) == len(data)
    
    def test_get_pattern_occurrences(self):
        data = pd.DataFrame({
            "timestamp": pd.date_range("2024-01-01", periods=5, freq="D"),
            "open": [100, 102, 99, 101, 100],
            "high": [103, 105, 102, 104, 103],
            "low": [99, 100, 97, 99, 98],
            "close": [102, 101, 100, 102, 101],
            "volume": [1000000] * 5,
        })
        
        occurrences = get_pattern_occurrences(data, ["hammer", "bullish_engulfing"])
        assert isinstance(occurrences, pd.DataFrame)
        if not occurrences.empty:
            assert "pattern" in occurrences.columns
            assert "date" in occurrences.columns
            assert "signal" in occurrences.columns


class TestPatternSignalsIntegration:
    """Integration tests for pattern signal generation."""
    
    def test_generate_signals_returns_series(self):
        data = pd.DataFrame({
            "timestamp": pd.date_range("2024-01-01", periods=20, freq="D"),
            "open": np.random.uniform(95, 105, 20),
            "high": np.random.uniform(100, 110, 20),
            "low": np.random.uniform(90, 100, 20),
            "close": np.random.uniform(95, 105, 20),
            "volume": np.random.randint(1000000, 5000000, 20),
        })
        # Ensure high >= max(open, close) and low <= min(open, close)
        data["high"] = data[["open", "close", "high"]].max(axis=1)
        data["low"] = data[["open", "close", "low"]].min(axis=1)
        
        signals = generate_pattern_signals(data, direction="both")
        
        assert isinstance(signals, pd.Series)
        assert len(signals) == len(data)
        assert set(signals.unique()).issubset({-1, 0, 1})
    
    def test_all_patterns_have_functions(self):
        for name, func in ALL_PATTERNS.items():
            assert callable(func), f"Pattern {name} is not callable"