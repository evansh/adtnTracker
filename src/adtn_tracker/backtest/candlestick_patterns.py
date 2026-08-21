"""Candlestick pattern detection module.

Implements traditional candlestick patterns for technical analysis.
Each pattern function returns a boolean Series indicating pattern occurrence.
"""

import pandas as pd
import numpy as np


def prepare_candlestick_data(data: pd.DataFrame) -> pd.DataFrame:
    """Prepare candlestick data with common derived columns."""
    df = data.copy()
    df["body"] = df["close"] - df["open"]
    df["body_abs"] = df["body"].abs()
    df["range"] = df["high"] - df["low"]
    df["upper_wick"] = df["high"] - df[["open", "close"]].max(axis=1)
    df["lower_wick"] = df[["open", "close"]].min(axis=1) - df["low"]
    df["is_bullish"] = df["body"] > 0
    df["is_bearish"] = df["body"] < 0
    df["is_doji"] = df["body_abs"] <= (df["range"] * 0.1)
    return df


# =============================================================================
# Single Candle Patterns
# =============================================================================

def hammer(df: pd.DataFrame) -> pd.Series:
    """Hammer - Bullish reversal at bottom of downtrend.
    
    Small body at top, long lower wick (2x body), little/no upper wick.
    """
    return (
        (df["lower_wick"] > 2 * df["body_abs"])
        & (df["upper_wick"] < 0.1 * df["range"])
        & (df["body_abs"] > 0)
    )


def inverted_hammer(df: pd.DataFrame) -> pd.Series:
    """Inverted Hammer - Bullish reversal at bottom.
    
    Small body at bottom, long upper wick (2x body), little/no lower wick.
    """
    return (
        (df["upper_wick"] > 2 * df["body_abs"])
        & (df["lower_wick"] < 0.1 * df["range"])
        & (df["body_abs"] > 0)
    )


def shooting_star(df: pd.DataFrame) -> pd.Series:
    """Shooting Star - Bearish reversal at top of uptrend.
    
    Small body at bottom, long upper wick (2x body), little/no lower wick.
    """
    return (
        (df["upper_wick"] > 2 * df["body_abs"])
        & (df["lower_wick"] < 0.1 * df["range"])
        & (df["body_abs"] > 0)
    )


def hanging_man(df: pd.DataFrame) -> pd.Series:
    """Hanging Man - Bearish reversal at top of uptrend.
    
    Same shape as hammer but appears at top of uptrend.
    """
    return (
        (df["lower_wick"] > 2 * df["body_abs"])
        & (df["upper_wick"] < 0.1 * df["range"])
        & (df["body_abs"] > 0)
    )


def doji(df: pd.DataFrame) -> pd.Series:
    """Doji - Indecision pattern.
    
    Open and close are nearly equal (body <= 10% of range).
    """
    return df["is_doji"]


def dragonfly_doji(df: pd.DataFrame) -> pd.Series:
    """Dragonfly Doji - Bullish reversal.
    
    Open=High=Close, long lower wick.
    """
    return (
        df["is_doji"]
        & (df["lower_wick"] > 0)
        & (df["upper_wick"] == 0)
    )


def gravestone_doji(df: pd.DataFrame) -> pd.Series:
    """Gravestone Doji - Bearish reversal.
    
    Open=Low=Close, long upper wick.
    """
    return (
        df["is_doji"]
        & (df["upper_wick"] > 0)
        & (df["lower_wick"] == 0)
    )


def marubozu_bullish(df: pd.DataFrame) -> pd.Series:
    """Bullish Marubozu - Strong bullish candle.
    
    No wicks, close > open (long white body).
    """
    return (
        (df["upper_wick"] == 0)
        & (df["lower_wick"] == 0)
        & df["is_bullish"]
    )


def marubozu_bearish(df: pd.DataFrame) -> pd.Series:
    """Bearish Marubozu - Strong bearish candle.
    
    No wicks, open > close (long black body).
    """
    return (
        (df["upper_wick"] == 0)
        & (df["lower_wick"] == 0)
        & df["is_bearish"]
    )


def spinning_top(df: pd.DataFrame) -> pd.Series:
    """Spinning Top - Indecision.
    
    Small body, long upper and lower wicks.
    """
    return (
        (df["body_abs"] < df["range"] * 0.3)
        & (df["upper_wick"] > df["body_abs"])
        & (df["lower_wick"] > df["body_abs"])
    )


# =============================================================================
# Two Candle Patterns
# =============================================================================

def bullish_engulfing(df: pd.DataFrame) -> pd.Series:
    """Bullish Engulfing - Bullish reversal.
    
    Small bearish candle followed by large bullish candle that engulfs it.
    """
    prev_bearish = df["is_bearish"].shift(1)
    curr_bullish = df["is_bullish"]
    
    return (
        prev_bearish
        & curr_bullish
        & (df["open"] < df["close"].shift(1))
        & (df["close"] > df["open"].shift(1))
    )


def bearish_engulfing(df: pd.DataFrame) -> pd.Series:
    """Bearish Engulfing - Bearish reversal.
    
    Small bullish candle followed by large bearish candle that engulfs it.
    """
    prev_bullish = df["is_bullish"].shift(1)
    curr_bearish = df["is_bearish"]
    
    return (
        prev_bullish
        & curr_bearish
        & (df["open"] > df["close"].shift(1))
        & (df["close"] < df["open"].shift(1))
    )


def bullish_harami(df: pd.DataFrame) -> pd.Series:
    """Bullish Harami - Bullish reversal.
    
    Large bearish candle followed by small bullish candle inside it.
    """
    prev_bearish = df["is_bearish"].shift(1)
    curr_bullish = df["is_bullish"]
    
    return (
        prev_bearish
        & curr_bullish
        & (df["open"] > df["close"].shift(1))
        & (df["close"] < df["open"].shift(1))
    )


def bearish_harami(df: pd.DataFrame) -> pd.Series:
    """Bearish Harami - Bearish reversal.
    
    Large bullish candle followed by small bearish candle inside it.
    """
    prev_bullish = df["is_bullish"].shift(1)
    curr_bearish = df["is_bearish"]
    
    return (
        prev_bullish
        & curr_bearish
        & (df["open"] < df["close"].shift(1))
        & (df["close"] > df["open"].shift(1))
    )


def piercing_line(df: pd.DataFrame) -> pd.Series:
    """Piercing Line - Bullish reversal.
    
    Bearish candle followed by bullish candle that opens lower but closes
    above midpoint of previous candle.
    """
    prev_bearish = df["is_bearish"].shift(1)
    curr_bullish = df["is_bullish"]
    prev_mid = (df["open"].shift(1) + df["close"].shift(1)) / 2
    
    return (
        prev_bearish
        & curr_bullish
        & (df["open"] < df["close"].shift(1))
        & (df["close"] > prev_mid)
    )


def dark_cloud_cover(df: pd.DataFrame) -> pd.Series:
    """Dark Cloud Cover - Bearish reversal.
    
    Bullish candle followed by bearish candle that opens higher but closes
    below midpoint of previous candle.
    """
    prev_bullish = df["is_bullish"].shift(1)
    curr_bearish = df["is_bearish"]
    prev_mid = (df["open"].shift(1) + df["close"].shift(1)) / 2
    
    return (
        prev_bullish
        & curr_bearish
        & (df["open"] > df["close"].shift(1))
        & (df["close"] < prev_mid)
    )


def tweezer_bottom(df: pd.DataFrame) -> pd.Series:
    """Tweezer Bottom - Bullish reversal.
    
    Two candles with same low.
    """
    return (
        (df["low"] == df["low"].shift(1))
        & (df["is_bearish"].shift(1) | df["is_bullish"].shift(1))
    )


def tweezer_top(df: pd.DataFrame) -> pd.Series:
    """Tweezer Top - Bearish reversal.
    
    Two candles with same high.
    """
    return (
        (df["high"] == df["high"].shift(1))
        & (df["is_bullish"].shift(1) | df["is_bearish"].shift(1))
    )


# =============================================================================
# Three Candle Patterns
# =============================================================================

def morning_star(df: pd.DataFrame) -> pd.Series:
    """Morning Star - Bullish reversal (3 candles).
    
    1. Large bearish candle
    2. Small candle (gap down)
    3. Large bullish candle (closes above midpoint of first)
    """
    c1_bearish = df["is_bearish"].shift(2)
    c2_small = (df["body_abs"].shift(1) < df["body_abs"].shift(2) * 0.3)
    c3_bullish = df["is_bullish"]
    c1_mid = (df["open"].shift(2) + df["close"].shift(2)) / 2
    
    return (
        c1_bearish
        & c2_small
        & c3_bullish
        & (df["close"] > c1_mid)
    )


def evening_star(df: pd.DataFrame) -> pd.Series:
    """Evening Star - Bearish reversal (3 candles).
    
    1. Large bullish candle
    2. Small candle (gap up)
    3. Large bearish candle (closes below midpoint of first)
    """
    c1_bullish = df["is_bullish"].shift(2)
    c2_small = (df["body_abs"].shift(1) < df["body_abs"].shift(2) * 0.3)
    c3_bearish = df["is_bearish"]
    c1_mid = (df["open"].shift(2) + df["close"].shift(2)) / 2
    
    return (
        c1_bullish
        & c2_small
        & c3_bearish
        & (df["close"] < c1_mid)
    )


def three_white_soldiers(df: pd.DataFrame) -> pd.Series:
    """Three White Soldiers - Bullish continuation.
    
    Three consecutive long bullish candles, each opening within previous body.
    """
    c1 = df["is_bullish"].shift(2)
    c2 = df["is_bullish"].shift(1)
    c3 = df["is_bullish"]
    
    return (
        c1 & c2 & c3
        & (df["open"].shift(1) > df["open"].shift(2))
        & (df["open"] > df["open"].shift(1))
        & (df["close"] > df["close"].shift(1))
        & (df["close"].shift(1) > df["close"].shift(2))
    )


def three_black_crows(df: pd.DataFrame) -> pd.Series:
    """Three Black Crows - Bearish continuation.
    
    Three consecutive long bearish candles, each opening within previous body.
    """
    c1 = df["is_bearish"].shift(2)
    c2 = df["is_bearish"].shift(1)
    c3 = df["is_bearish"]
    
    return (
        c1 & c2 & c3
        & (df["open"].shift(1) < df["open"].shift(2))
        & (df["open"] < df["open"].shift(1))
        & (df["close"] < df["close"].shift(1))
        & (df["close"].shift(1) < df["close"].shift(2))
    )


def three_inside_up(df: pd.DataFrame) -> pd.Series:
    """Three Inside Up - Bullish reversal (3 candles).
    
    1. Large bearish
    2. Bullish harami
    3. Bullish confirmation
    """
    c1_bearish = df["is_bearish"].shift(2)
    c2_harami = (
        df["is_bullish"].shift(1)
        & (df["open"].shift(1) > df["close"].shift(2))
        & (df["close"].shift(1) < df["open"].shift(2))
    )
    c3_bullish = df["is_bullish"]
    c3_confirm = df["close"] > df["close"].shift(1)
    
    return c1_bearish & c2_harami & c3_bullish & c3_confirm


def three_inside_down(df: pd.DataFrame) -> pd.Series:
    """Three Inside Down - Bearish reversal (3 candles).
    
    1. Large bullish
    2. Bearish harami
    3. Bearish confirmation
    """
    c1_bullish = df["is_bullish"].shift(2)
    c2_harami = (
        df["is_bearish"].shift(1)
        & (df["open"].shift(1) < df["close"].shift(2))
        & (df["close"].shift(1) > df["open"].shift(2))
    )
    c3_bearish = df["is_bearish"]
    c3_confirm = df["close"] < df["close"].shift(1)
    
    return c1_bullish & c2_harami & c3_bearish & c3_confirm


# =============================================================================
# Pattern Registry
# =============================================================================

# Map pattern names to functions
BULLISH_PATTERNS = {
    "hammer": hammer,
    "inverted_hammer": inverted_hammer,
    "dragonfly_doji": dragonfly_doji,
    "marubozu_bullish": marubozu_bullish,
    "bullish_engulfing": bullish_engulfing,
    "bullish_harami": bullish_harami,
    "piercing_line": piercing_line,
    "tweezer_bottom": tweezer_bottom,
    "morning_star": morning_star,
    "three_white_soldiers": three_white_soldiers,
    "three_inside_up": three_inside_up,
}

BEARISH_PATTERNS = {
    "shooting_star": shooting_star,
    "hanging_man": hanging_man,
    "gravestone_doji": gravestone_doji,
    "marubozu_bearish": marubozu_bearish,
    "bearish_engulfing": bearish_engulfing,
    "bearish_harami": bearish_harami,
    "dark_cloud_cover": dark_cloud_cover,
    "tweezer_top": tweezer_top,
    "evening_star": evening_star,
    "three_black_crows": three_black_crows,
    "three_inside_down": three_inside_down,
}

NEUTRAL_PATTERNS = {
    "doji": doji,
    "spinning_top": spinning_top,
}


ALL_PATTERNS = {**BULLISH_PATTERNS, **BEARISH_PATTERNS, **NEUTRAL_PATTERNS}


def generate_pattern_signals(
    data: pd.DataFrame,
    patterns: list[str] = None,
    direction: str = "both",
) -> pd.Series:
    """Generate signals from multiple candlestick patterns.
    
    Args:
        data: DataFrame with OHLCV data
        patterns: List of pattern names to use (None = all)
        direction: "bullish", "bearish", or "both"
    
    Returns:
        Series with 1 (long), -1 (short), 0 (flat)
    """
    df = prepare_candlestick_data(data)
    signals = pd.Series(0, index=df.index)
    
    if patterns is None:
        patterns = list(ALL_PATTERNS.keys())
    
    if direction in ("bullish", "both"):
        for name in patterns:
            if name in BULLISH_PATTERNS:
                signals[BULLISH_PATTERNS[name](df)] = 1
    
    if direction in ("bearish", "both"):
        for name in patterns:
            if name in BEARISH_PATTERNS:
                signals[BEARISH_PATTERNS[name](df)] = -1
    
    return signals


def get_pattern_occurrences(
    data: pd.DataFrame,
    patterns: list[str] = None,
) -> pd.DataFrame:
    """Get all pattern occurrences for analysis.
    
    Returns DataFrame with columns: pattern, date, signal (1/-1/0)
    """
    df = prepare_candlestick_data(data)
    
    if patterns is None:
        patterns = list(ALL_PATTERNS.keys())
    
    occurrences = []
    for name in patterns:
        if name in ALL_PATTERNS:
            pattern_signals = ALL_PATTERNS[name](df)
            for idx, val in pattern_signals.items():
                if val:
                    signal = 1 if name in BULLISH_PATTERNS else (-1 if name in BEARISH_PATTERNS else 0)
                    occurrences.append({
                        "pattern": name,
                        "date": df.loc[idx, "timestamp"] if "timestamp" in df.columns else idx,
                        "signal": signal,
                        "close": df.loc[idx, "close"],
                    })
    
    return pd.DataFrame(occurrences)