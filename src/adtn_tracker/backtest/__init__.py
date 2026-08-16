"""Vectorized backtester for adtn_tracker."""

import logging
from dataclasses import dataclass
from datetime import datetime
from typing import Optional

import numpy as np
import pandas as pd

logger = logging.getLogger(__name__)


@dataclass
class BacktestConfig:
    """Configuration for backtest."""

    initial_capital: float = 100000.0
    position_size_pct: float = 0.10
    commission_per_share: float = 0.005
    slippage_pct: float = 0.001
    min_trade_size: int = 1


@dataclass
class Trade:
    """Represents a completed trade."""

    entry_date: datetime
    exit_date: datetime
    symbol: str
    side: str
    entry_price: float
    exit_price: float
    shares: int
    pnl: float
    return_pct: float


class SimpleBacktester:
    """Simple vectorized backtester for equity strategies."""

    def __init__(self, config: BacktestConfig | None = None):
        self.config = config or BacktestConfig()
        self.trades: list[Trade] = []
        self.equity_curve: pd.Series = pd.Series(dtype=float)

    def run(
        self,
        data: pd.DataFrame,
        signals: pd.Series,
    ) -> dict:
        """Run backtest on price data with signals.

        Args:
            data: DataFrame with columns ['symbol', 'timestamp', 'open', 'high', 'low', 'close', 'volume']
            signals: Series with 1 for long entry, -1 for short entry, 0 for flat/exit

        Returns:
            Dictionary with trades, equity curve, and performance metrics
        """
        df = data.copy()
        df = df.sort_values("timestamp").reset_index(drop=True)
        signals = signals.reindex(df.index).fillna(0)

        position = 0
        entry_price = 0.0
        entry_date = None
        shares = 0
        cash = self.config.initial_capital
        equity = []

        for i, row in df.iterrows():
            signal = signals.iloc[i]
            price = row["close"]

            if position == 0 and signal != 0:
                position = 1 if signal > 0 else -1
                entry_price = price * (1 + self.config.slippage_pct * position)
                entry_date = row["timestamp"]
                trade_value = cash * self.config.position_size_pct
                shares = max(int(trade_value / entry_price), self.config.min_trade_size)
                cost = shares * entry_price + shares * self.config.commission_per_share
                if cost > cash:
                    shares = int((cash - shares * self.config.commission_per_share) / entry_price)
                    cost = shares * entry_price + shares * self.config.commission_per_share
                if shares < self.config.min_trade_size:
                    position = 0
                    continue
                cash -= cost
                logger.debug(
                    f"Enter {position} {shares} shares at {entry_price:.2f} on {entry_date}"
                )

            elif position != 0 and signal == 0:
                exit_price = price * (1 - self.config.slippage_pct * position)
                exit_date = row["timestamp"]

                if position > 0:
                    # Long position: buy at entry, sell at exit
                    proceeds = shares * exit_price - shares * self.config.commission_per_share
                    pnl = (
                        proceeds - shares * entry_price - shares * self.config.commission_per_share
                    )
                else:
                    # Short position: sell at entry, buy at exit
                    # Initially received: shares * entry_price
                    # Pay to cover: shares * exit_price + commission
                    proceeds = (
                        shares * entry_price
                        - shares * exit_price
                        - shares * self.config.commission_per_share
                    )
                    pnl = proceeds - shares * self.config.commission_per_share

                cash += (
                    shares * exit_price - shares * self.config.commission_per_share
                    if position > 0
                    else shares * entry_price
                    - shares * exit_price
                    - shares * self.config.commission_per_share
                )
                return_pct = pnl / (shares * entry_price)

                self.trades.append(
                    Trade(
                        entry_date=entry_date,
                        exit_date=exit_date,
                        symbol=row["symbol"],
                        side="long" if position > 0 else "short",
                        entry_price=entry_price,
                        exit_price=exit_price,
                        shares=shares,
                        pnl=pnl,
                        return_pct=return_pct,
                    )
                )
                logger.debug(
                    f"Exit {position} {shares} shares at {exit_price:.2f} on {exit_date}, PnL={pnl:.2f}"
                )
                position = 0
                entry_price = 0.0
                shares = 0

            current_equity = cash
            if position != 0:
                current_equity += shares * price
            equity.append(current_equity)

        self.equity_curve = pd.Series(equity, index=df["timestamp"])
        return self._compute_metrics()

    def _compute_metrics(self) -> dict:
        """Compute performance metrics."""
        if len(self.equity_curve) == 0:
            return {}

        returns = self.equity_curve.pct_change().dropna()
        total_return = (self.equity_curve.iloc[-1] / self.equity_curve.iloc[0]) - 1
        n_periods = len(returns)
        years = n_periods / 252

        cagr = (1 + total_return) ** (1 / years) - 1 if years > 0 else 0
        sharpe = (returns.mean() / returns.std() * np.sqrt(252)) if returns.std() > 0 else 0
        max_drawdown = self._max_drawdown()
        win_rate = self._win_rate()
        profit_factor = self._profit_factor()

        return {
            "total_return": total_return,
            "cagr": cagr,
            "sharpe": sharpe,
            "max_drawdown": max_drawdown,
            "win_rate": win_rate,
            "profit_factor": profit_factor,
            "num_trades": len(self.trades),
            "final_equity": self.equity_curve.iloc[-1],
        }

    def _max_drawdown(self) -> float:
        peak = self.equity_curve.expanding().max()
        drawdown = (self.equity_curve - peak) / peak
        return drawdown.min()

    def _win_rate(self) -> float:
        if not self.trades:
            return 0.0
        wins = sum(1 for t in self.trades if t.pnl > 0)
        return wins / len(self.trades)

    def _profit_factor(self) -> float:
        if not self.trades:
            return 0.0
        gross_profit = sum(t.pnl for t in self.trades if t.pnl > 0)
        gross_loss = abs(sum(t.pnl for t in self.trades if t.pnl < 0))
        return gross_profit / gross_loss if gross_loss > 0 else float("inf")

    def get_trades_df(self) -> pd.DataFrame:
        """Return trades as DataFrame."""
        if not self.trades:
            return pd.DataFrame(
                columns=[
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
            )
        return pd.DataFrame(
            [
                {
                    "entry_date": t.entry_date,
                    "exit_date": t.exit_date,
                    "symbol": t.symbol,
                    "side": t.side,
                    "entry_price": t.entry_price,
                    "exit_price": t.exit_price,
                    "shares": t.shares,
                    "pnl": t.pnl,
                    "return_pct": t.return_pct,
                }
                for t in self.trades
            ]
        )

    def get_equity_curve_df(self) -> pd.DataFrame:
        """Return equity curve as DataFrame."""
        return self.equity_curve.reset_index().rename(columns={"index": "timestamp", 0: "equity"})


def generate_candlestick_signals(data: pd.DataFrame, lookback: int = 5) -> pd.Series:
    """Generate simple candlestick pattern signals for demonstration.

    Args:
        data: DataFrame with OHLCV data
        lookback: Number of periods for pattern confirmation

    Returns:
        Series with 1 (long), -1 (short), 0 (flat)
    """
    df = data.copy()
    df["body"] = df["close"] - df["open"]
    df["body_abs"] = df["body"].abs()
    df["range"] = df["high"] - df["low"]
    df["upper_wick"] = df["high"] - df[["open", "close"]].max(axis=1)
    df["lower_wick"] = df[["open", "close"]].min(axis=1) - df["low"]

    signals = pd.Series(0, index=df.index)

    bullish_engulfing = (
        (df["body"].shift(1) < 0)
        & (df["body"] > 0)
        & (df["open"] < df["close"].shift(1))
        & (df["close"] > df["open"].shift(1))
    )

    bearish_engulfing = (
        (df["body"].shift(1) > 0)
        & (df["body"] < 0)
        & (df["open"] > df["close"].shift(1))
        & (df["close"] < df["open"].shift(1))
    )

    hammer = (
        (df["lower_wick"] > 2 * df["body_abs"])
        & (df["upper_wick"] < 0.1 * df["range"])
        & (df["body_abs"] > 0)
    )

    shooting_star = (
        (df["upper_wick"] > 2 * df["body_abs"])
        & (df["lower_wick"] < 0.1 * df["range"])
        & (df["body_abs"] > 0)
    )

    signals[bullish_engulfing | hammer] = 1
    signals[bearish_engulfing | shooting_star] = -1

    return signals


def generate_sma_crossover_signals(data: pd.DataFrame, fast: int = 10, slow: int = 30) -> pd.Series:
    """Generate SMA crossover signals.

    Args:
        data: DataFrame with OHLCV data
        fast: Fast SMA period
        slow: Slow SMA period

    Returns:
        Series with 1 (long), -1 (short), 0 (flat)
    """
    df = data.copy()
    df["fast_sma"] = df["close"].rolling(fast).mean()
    df["slow_sma"] = df["close"].rolling(slow).mean()

    signals = pd.Series(0, index=df.index)

    # Golden cross
    golden = (df["fast_sma"].shift(1) <= df["slow_sma"].shift(1)) & (
        df["fast_sma"] > df["slow_sma"]
    )
    # Death cross
    death = (df["fast_sma"].shift(1) >= df["slow_sma"].shift(1)) & (df["fast_sma"] < df["slow_sma"])

    signals[golden] = 1
    signals[death] = -1

    return signals
