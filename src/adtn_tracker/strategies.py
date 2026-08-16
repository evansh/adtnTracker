"""Example strategies using the new architecture."""

from datetime import datetime

import pandas as pd

from .core import (
    Bar,
    Order,
    OrderSide,
    OrderType,
    Quote,
    Strategy,
    Symbol,
)


class CandlestickPatternStrategy(Strategy):
    """Candlestick pattern strategy (engulfing, hammer, shooting star)."""

    def __init__(
        self,
        name: str,
        symbols: list[Symbol],
        lookback: int = 5,
        position_size_pct: float = 0.10,
    ):
        super().__init__(name, symbols)
        self.lookback = lookback
        self.position_size_pct = position_size_pct
        self._bars_buffer: dict[Symbol, list[Bar]] = {s: [] for s in symbols}
        self._positions: dict[Symbol, float] = dict.fromkeys(symbols, 0.0)

    def on_bar(self, bar: Bar) -> list[Order]:
        """Process new bar and generate signals."""
        orders = []

        # Add to buffer
        self._bars_buffer[bar.symbol].append(bar)
        if len(self._bars_buffer[bar.symbol]) > self.lookback:
            self._bars_buffer[bar.symbol].pop(0)

        # Need enough bars
        if len(self._bars_buffer[bar.symbol]) < self.lookback:
            return orders

        # Generate signal
        signal = self._generate_signal(bar.symbol)

        current_pos = self._positions[bar.symbol]

        if signal == 1 and current_pos <= 0:
            # Long entry
            orders.append(
                Order(
                    order_id=f"{self.name}_{bar.symbol.ticker}_{datetime.now().timestamp()}",
                    account_id="default",
                    symbol=bar.symbol,
                    side=OrderSide.BUY,
                    order_type=OrderType.MARKET,
                    quantity=100,  # Will be calculated by executor
                )
            )
            self._positions[bar.symbol] = 1

        elif signal == -1 and current_pos >= 0:
            # Short entry (or exit long)
            orders.append(
                Order(
                    order_id=f"{self.name}_{bar.symbol.ticker}_{datetime.now().timestamp()}",
                    account_id="default",
                    symbol=bar.symbol,
                    side=OrderSide.SELL,
                    order_type=OrderType.MARKET,
                    quantity=100,
                )
            )
            self._positions[bar.symbol] = -1

        elif signal == 0 and current_pos != 0:
            # Exit
            side = OrderSide.SELL if current_pos > 0 else OrderSide.BUY
            orders.append(
                Order(
                    order_id=f"{self.name}_{bar.symbol.ticker}_{datetime.now().timestamp()}",
                    account_id="default",
                    symbol=bar.symbol,
                    side=side,
                    order_type=OrderType.MARKET,
                    quantity=abs(current_pos),
                )
            )
            self._positions[bar.symbol] = 0

        return orders

    def _generate_signal(self, symbol: Symbol) -> int:
        """Generate signal from candlestick patterns."""
        bars = self._bars_buffer[symbol]
        if len(bars) < 2:
            return 0

        df = pd.DataFrame(
            [
                {
                    "open": b.open,
                    "high": b.high,
                    "low": b.low,
                    "close": b.close,
                }
                for b in bars
            ]
        )

        df["body"] = df["close"] - df["open"]
        df["body_abs"] = df["body"].abs()
        df["range"] = df["high"] - df["low"]
        df["upper_wick"] = df["high"] - df[["open", "close"]].max(axis=1)
        df["lower_wick"] = df[["open", "close"]].min(axis=1) - df["low"]

        prev = df.iloc[-2]
        curr = df.iloc[-1]

        # Bullish engulfing
        bullish_engulfing = (
            prev["body"] < 0
            and curr["body"] > 0
            and curr["open"] < prev["close"]
            and curr["close"] > prev["open"]
        )

        # Bearish engulfing
        bearish_engulfing = (
            prev["body"] > 0
            and curr["body"] < 0
            and curr["open"] > prev["close"]
            and curr["close"] < prev["open"]
        )

        # Hammer
        hammer = (
            curr["lower_wick"] > 2 * curr["body_abs"]
            and curr["upper_wick"] < 0.1 * curr["range"]
            and curr["body_abs"] > 0
        )

        # Shooting star
        shooting_star = (
            curr["upper_wick"] > 2 * curr["body_abs"]
            and curr["lower_wick"] < 0.1 * curr["range"]
            and curr["body_abs"] > 0
        )

        if bullish_engulfing or hammer:
            return 1
        elif bearish_engulfing or shooting_star:
            return -1
        return 0

    def on_quote(self, _quote: Quote) -> list[Order]:
        return []


class MovingAverageCrossoverStrategy(Strategy):
    """Simple moving average crossover strategy."""

    def __init__(
        self,
        name: str,
        symbols: list[Symbol],
        fast_period: int = 10,
        slow_period: int = 30,
    ):
        super().__init__(name, symbols)
        self.fast_period = fast_period
        self.slow_period = slow_period
        self._closes: dict[Symbol, list[float]] = {s: [] for s in symbols}
        self._positions: dict[Symbol, int] = dict.fromkeys(symbols, 0)

    def on_bar(self, bar: Bar) -> list[Order]:
        orders = []

        self._closes[bar.symbol].append(bar.close)
        if len(self._closes[bar.symbol]) > self.slow_period:
            self._closes[bar.symbol].pop(0)

        if len(self._closes[bar.symbol]) < self.slow_period:
            return orders

        closes = pd.Series(self._closes[bar.symbol])
        fast_ma = closes.rolling(self.fast_period).mean().iloc[-1]
        slow_ma = closes.rolling(self.slow_period).mean().iloc[-1]
        prev_fast = closes.rolling(self.fast_period).mean().iloc[-2]
        prev_slow = closes.rolling(self.slow_period).mean().iloc[-2]

        current_pos = self._positions[bar.symbol]

        # Golden cross
        if prev_fast <= prev_slow and fast_ma > slow_ma and current_pos <= 0:
            orders.append(
                Order(
                    order_id=f"{self.name}_{bar.symbol.ticker}_{datetime.now().timestamp()}",
                    account_id="default",
                    symbol=bar.symbol,
                    side=OrderSide.BUY,
                    order_type=OrderType.MARKET,
                    quantity=100,
                )
            )
            self._positions[bar.symbol] = 1

        # Death cross
        elif prev_fast >= prev_slow and fast_ma < slow_ma and current_pos >= 0:
            orders.append(
                Order(
                    order_id=f"{self.name}_{bar.symbol.ticker}_{datetime.now().timestamp()}",
                    account_id="default",
                    symbol=bar.symbol,
                    side=OrderSide.SELL,
                    order_type=OrderType.MARKET,
                    quantity=100,
                )
            )
            self._positions[bar.symbol] = -1

        return orders

    def on_quote(self, _quote: Quote) -> list[Order]:
        return []
