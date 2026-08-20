"""Value Wheel Strategy - Buy near yearly lows, sell covered calls."""

from dataclasses import dataclass
from datetime import datetime
from typing import Optional
import pandas as pd
import numpy as np

from adtn_tracker.core import (
    Strategy,
    Symbol,
    Bar,
    Order,
    OrderSide,
    OrderType,
    Quote,
    TimeFrame,
)
from adtn_tracker.backtest import SimpleBacktester, BacktestConfig


@dataclass
class ValueWheelConfig:
    """Configuration for Value Wheel Strategy."""
    # Entry criteria
    lookback_years: int = 5
    buy_zone_pct: float = 0.10  # Within 10% of yearly low average
    
    # Position sizing
    initial_capital: float = 100000.0
    position_size_pct: float = 0.20  # 20% per position
    max_positions: int = 3
    
    # Option selling
    call_strike: float = 15.0  # Fixed $15 strike
    min_days_to_expiry: int = 30
    max_days_to_expiry: int = 45
    
    # Risk management
    stop_loss_pct: float = 0.20  # 20% stop loss
    take_profit_pct: float = 0.50  # 50% take profit on stock
    
    # Reinvestment
    reinvest_premiums: bool = True
    min_premium_to_reinvest: float = 100.0


@dataclass
class YearlyStats:
    """Statistics for a given year."""
    year: int
    low: float
    high: float
    avg_price: float
    avg_low: float  # Average of monthly lows


class ValueWheelStrategy(Strategy):
    """Value Wheel Strategy: Buy near yearly lows, sell covered calls at fixed strike."""
    
    def __init__(
        self,
        name: str,
        symbols: list[Symbol],
        config: Optional[ValueWheelConfig] = None,
    ):
        super().__init__(name, symbols)
        self.config = config or ValueWheelConfig()
        self._yearly_stats: dict[int, YearlyStats] = {}
        self._buy_threshold: float = 0.0
        self._positions: dict[Symbol, dict] = {}
        self._option_premiums_collected: float = 0.0
        self._shares_owned: dict[Symbol, int] = {}
        self._cost_basis: dict[Symbol, float] = {}
    
    def on_start(self) -> None:
        """Calculate yearly statistics and buy threshold."""
        # This would be called with historical data
        pass
    
    def calculate_yearly_stats(self, data: pd.DataFrame) -> dict[int, YearlyStats]:
        """Calculate yearly statistics from historical data."""
        data = data.copy()
        data['year'] = data['timestamp'].dt.year
        data['month'] = data['timestamp'].dt.month
        
        yearly_stats = {}
        for year, year_data in data.groupby('year'):
            monthly_lows = year_data.groupby('month')['low'].min()
            yearly_stats[year] = YearlyStats(
                year=year,
                low=year_data['low'].min(),
                high=year_data['high'].max(),
                avg_price=year_data['close'].mean(),
                avg_low=monthly_lows.mean(),
            )
        return yearly_stats
    
    def compute_buy_threshold(self, yearly_stats: dict[int, YearlyStats]) -> float:
        """Compute buy threshold as average of yearly lows * (1 + buy_zone_pct)."""
        if not yearly_stats:
            return 0.0
        avg_yearly_low = np.mean([s.avg_low for s in yearly_stats.values()])
        return avg_yearly_low * (1 + self.config.buy_zone_pct)
    
    def should_buy(self, current_price: float) -> bool:
        """Check if current price is in buy zone."""
        return current_price <= self._buy_threshold and current_price > 0
    
    def calculate_position_size(self, price: float, available_cash: float) -> int:
        """Calculate number of shares to buy."""
        position_value = available_cash * self.config.position_size_pct
        shares = int(position_value / price)
        # Round to 100 shares for options
        return (shares // 100) * 100 if shares >= 100 else 0
    
    def on_bar(self, bar: Bar) -> list[Order]:
        orders = []
        
        # Update buy threshold if not set
        if self._buy_threshold == 0 and hasattr(self, '_historical_data'):
            self._yearly_stats = self.calculate_yearly_stats(self._historical_data)
            self._buy_threshold = self.compute_buy_threshold(self._yearly_stats)
        
        symbol = bar.symbol
        price = bar.close
        pos = self._positions.get(symbol, {})
        
        # Check if we should buy
        if not pos and self.should_buy(price):
            # We need cash info - simplified here
            shares = self.calculate_position_size(price, self.config.initial_capital * 0.5)
            if shares >= 100:
                orders.append(Order(
                    order_id=f"{self.name}_buy_{symbol.ticker}_{datetime.now().timestamp()}",
                    account_id="default",
                    symbol=symbol,
                    side=OrderSide.BUY,
                    order_type=OrderType.MARKET,
                    quantity=shares,
                ))
                self._positions[symbol] = {
                    'shares': shares,
                    'entry_price': price,
                    'entry_date': bar.timestamp,
                    'calls_sold': 0,
                }
                self._shares_owned[symbol] = shares
                self._cost_basis[symbol] = price
        
        # Manage existing position
        elif pos:
            shares = pos['shares']
            entry_price = pos['entry_price']
            pnl_pct = (price - entry_price) / entry_price
            
            # Stop loss
            if pnl_pct <= -self.config.stop_loss_pct:
                orders.append(Order(
                    order_id=f"{self.name}_stop_{symbol.ticker}_{datetime.now().timestamp()}",
                    account_id="default",
                    symbol=symbol,
                    side=OrderSide.SELL,
                    order_type=OrderType.MARKET,
                    quantity=shares,
                ))
                self._positions.pop(symbol, None)
                self._shares_owned.pop(symbol, None)
                return orders
            
            # Take profit
            if pnl_pct >= self.config.take_profit_pct:
                orders.append(Order(
                    order_id=f"{self.name}_profit_{symbol.ticker}_{datetime.now().timestamp()}",
                    account_id="default",
                    symbol=symbol,
                    side=OrderSide.SELL,
                    order_type=OrderType.MARKET,
                    quantity=shares,
                ))
                self._positions.pop(symbol, None)
                self._shares_owned.pop(symbol, None)
                return orders
            
            # Sell covered calls if we have 100+ shares
            if shares >= 100 and pos.get('calls_sold', 0) == 0:
                # Check if strike is above current price (OTM)
                if self.config.call_strike > price * 1.02:  # At least 2% OTM
                    contracts = shares // 100
                    orders.append(Order(
                        order_id=f"{self.name}_call_{symbol.ticker}_{datetime.now().timestamp()}",
                        account_id="default",
                        symbol=Symbol(
                            ticker=f"{symbol.ticker} {self.config.call_strike}C",
                            asset_class="option",
                        ),
                        side=OrderSide.SELL,
                        order_type=OrderType.LIMIT,
                        quantity=contracts,
                        limit_price=0.50,  # Minimum premium
                    ))
                    pos['calls_sold'] = contracts
                    pos['call_strike'] = self.config.call_strike
        
        return orders
    
    def on_quote(self, quote: Quote) -> list[Order]:
        return []

    def on_stop(self) -> None:
        pass


def run_value_wheel_backtest(
    symbol: str = "ADTN",
    years: int = 5,
    config: Optional[ValueWheelConfig] = None,
) -> dict:
    """Run backtest for Value Wheel Strategy."""
    from adtn_tracker.data import YFinanceProvider
    from adtn_tracker.config import get_settings
    
    cfg = config or ValueWheelConfig()
    provider = YFinanceProvider(get_settings().yfinance)
    provider.connect()
    
    sym = Symbol(ticker=symbol)
    end = datetime.now()
    start = end.replace(year=end.year - years)
    
    bars = provider.get_bars(sym, TimeFrame.DAY_1, start, end)
    if not bars:
        return {"error": "No data"}
    
    df = pd.DataFrame([{
        'timestamp': b.timestamp,
        'open': b.open,
        'high': b.high,
        'low': b.low,
        'close': b.close,
        'volume': b.volume,
    } for b in bars])
    
    # Calculate stats
    strategy = ValueWheelStrategy("value_wheel", [sym], cfg)
    yearly_stats = strategy.calculate_yearly_stats(df)
    buy_threshold = strategy.compute_buy_threshold(yearly_stats)
    
    print(f"Yearly Stats:")
    for y, s in yearly_stats.items():
        print(f"  {y}: Low={s.low:.2f}, High={s.high:.2f}, AvgLow={s.avg_low:.2f}")
    print(f"Buy Threshold: ${buy_threshold:.2f}")
    print(f"Current Price: ${df['close'].iloc[-1]:.2f}")
    print(f"In Buy Zone: {df['close'].iloc[-1] <= buy_threshold}")
    
    return {
        'yearly_stats': yearly_stats,
        'buy_threshold': buy_threshold,
        'current_price': df['close'].iloc[-1],
    }


if __name__ == "__main__":
    from adtn_tracker.core import TimeFrame
    result = run_value_wheel_backtest("ADTN", 5)
    print(result)