"""Core abstract base classes for adtn_tracker (SOLID principles)."""

from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import datetime
from enum import Enum


class TimeFrame(str, Enum):
    """Supported timeframes for market data."""

    MINUTE_1 = "1m"
    MINUTE_5 = "5m"
    MINUTE_15 = "15m"
    MINUTE_30 = "30m"
    HOUR_1 = "1h"
    DAY_1 = "1d"
    WEEK_1 = "1wk"
    MONTH_1 = "1mo"


class OrderSide(str, Enum):
    """Order side."""

    BUY = "buy"
    SELL = "sell"


class OrderType(str, Enum):
    """Order type."""

    MARKET = "market"
    LIMIT = "limit"
    STOP = "stop"
    STOP_LIMIT = "stop_limit"


class OrderStatus(str, Enum):
    """Order status."""

    PENDING = "pending"
    OPEN = "open"
    FILLED = "filled"
    PARTIALLY_FILLED = "partially_filled"
    CANCELLED = "cancelled"
    REJECTED = "rejected"
    EXPIRED = "expired"


class AssetClass(str, Enum):
    """Asset class."""

    EQUITY = "equity"
    OPTION = "option"
    FUTURE = "future"
    FOREX = "forex"
    CRYPTO = "crypto"


@dataclass(frozen=True)
class Symbol:
    """Universal symbol representation."""

    ticker: str
    asset_class: AssetClass = AssetClass.EQUITY
    exchange: str | None = None

    def __str__(self) -> str:
        if self.exchange:
            return f"{self.exchange}:{self.ticker}"
        return self.ticker

    @classmethod
    def from_string(cls, s: str) -> "Symbol":
        if ":" in s:
            exchange, ticker = s.split(":", 1)
            return cls(ticker=ticker.upper(), exchange=exchange.upper())
        return cls(ticker=s.upper())


@dataclass
class Quote:
    """Real-time quote."""

    symbol: Symbol
    bid: float
    ask: float
    bid_size: int
    ask_size: int
    last: float
    timestamp: datetime
    raw: dict = None


@dataclass
class Bar:
    """OHLCV bar."""

    symbol: Symbol
    timestamp: datetime
    open: float
    high: float
    low: float
    close: float
    volume: int
    vwap: float | None = None
    raw: dict = None


@dataclass
class OptionContract:
    """Option contract specification."""

    symbol: Symbol
    underlying: Symbol
    strike: float
    expiration: datetime
    option_type: str  # 'call' or 'put'
    multiplier: int = 100


@dataclass
class OptionQuote:
    """Option quote with Greeks."""

    contract: OptionContract
    bid: float
    ask: float
    last: float
    volume: int
    open_interest: int
    implied_volatility: float | None = None
    delta: float | None = None
    gamma: float | None = None
    theta: float | None = None
    vega: float | None = None
    rho: float | None = None
    timestamp: datetime = None
    raw: dict = None


@dataclass
class Account:
    """Brokerage account."""

    account_id: str
    name: str
    buying_power: float
    cash: float
    equity: float
    currency: str = "USD"
    raw: dict = None


@dataclass
class Position:
    """Current position."""

    account_id: str
    symbol: Symbol
    quantity: float
    avg_entry_price: float
    current_price: float
    market_value: float
    unrealized_pnl: float
    raw: dict = None


@dataclass
class Order:
    """Order representation."""

    order_id: str
    account_id: str
    symbol: Symbol
    side: OrderSide
    order_type: OrderType
    quantity: float
    limit_price: float | None = None
    stop_price: float | None = None
    status: OrderStatus = OrderStatus.PENDING
    filled_quantity: float = 0.0
    avg_fill_price: float | None = None
    created_at: datetime = None
    updated_at: datetime = None
    raw: dict = None


class DataProvider(ABC):
    """Abstract base class for market data providers."""

    @abstractmethod
    def connect(self) -> None:
        """Establish connection to data provider."""
        pass

    @abstractmethod
    def disconnect(self) -> None:
        """Close connection."""
        pass

    @abstractmethod
    def is_connected(self) -> bool:
        """Check connection status."""
        pass

    @abstractmethod
    def get_bars(
        self,
        symbol: Symbol,
        timeframe: TimeFrame,
        start: datetime,
        end: datetime | None = None,
        limit: int | None = None,
    ) -> list[Bar]:
        """Get historical bars."""
        pass

    @abstractmethod
    def get_latest_bar(self, symbol: Symbol, timeframe: TimeFrame) -> Bar | None:
        """Get most recent bar."""
        pass

    @abstractmethod
    def get_quote(self, symbol: Symbol) -> Quote:
        """Get real-time quote."""
        pass

    @abstractmethod
    def get_option_chain(
        self,
        underlying: Symbol,
        expiration: datetime | None = None,
    ) -> list[OptionContract]:
        """Get option chain."""
        pass

    @abstractmethod
    def get_option_quote(self, contract: OptionContract) -> OptionQuote:
        """Get option quote with Greeks."""
        pass

    @abstractmethod
    def subscribe_bars(self, symbols: list[Symbol], timeframe: TimeFrame, callback) -> None:
        """Subscribe to real-time bars (WebSocket)."""
        pass

    @abstractmethod
    def unsubscribe_bars(self, symbols: list[Symbol]) -> None:
        """Unsubscribe from real-time bars."""
        pass


class Broker(ABC):
    """Abstract base class for brokerage integrations."""

    @abstractmethod
    def connect(self) -> None:
        """Establish connection to broker."""
        pass

    @abstractmethod
    def disconnect(self) -> None:
        """Close connection."""
        pass

    @abstractmethod
    def is_connected(self) -> bool:
        """Check connection status."""
        pass

    @abstractmethod
    def get_accounts(self) -> list[Account]:
        """Get all accounts."""
        pass

    @abstractmethod
    def get_account(self, account_id: str) -> Account:
        """Get specific account."""
        pass

    @abstractmethod
    def get_positions(self, account_id: str) -> list[Position]:
        """Get positions for account."""
        pass

    @abstractmethod
    def get_orders(
        self,
        account_id: str,
        status: OrderStatus | None = None,
        limit: int = 100,
    ) -> list[Order]:
        """Get orders for account."""
        pass

    @abstractmethod
    def place_order(self, order: Order) -> Order:
        """Place a new order."""
        pass

    @abstractmethod
    def cancel_order(self, account_id: str, order_id: str) -> bool:
        """Cancel an order."""
        pass

    @abstractmethod
    def replace_order(self, account_id: str, order_id: str, order: Order) -> Order:
        """Replace an existing order."""
        pass

    @abstractmethod
    def get_order(self, account_id: str, order_id: str) -> Order:
        """Get order details."""
        pass


class Strategy(ABC):
    """Abstract base class for trading strategies."""

    def __init__(self, name: str, symbols: list[Symbol], params: dict = None):
        self.name = name
        self.symbols = symbols
        self.params = params or {}
        self._data_provider: DataProvider | None = None
        self._broker: Broker | None = None

    @property
    def data_provider(self) -> DataProvider:
        if self._data_provider is None:
            raise RuntimeError("Data provider not set")
        return self._data_provider

    @data_provider.setter
    def data_provider(self, provider: DataProvider):
        self._data_provider = provider

    @property
    def broker(self) -> Broker:
        if self._broker is None:
            raise RuntimeError("Broker not set")
        return self._broker

    @broker.setter
    def broker(self, broker: Broker):
        self._broker = broker

    @abstractmethod
    def on_bar(self, bar: Bar) -> list[Order]:
        """Process new bar and return orders to place."""
        pass

    @abstractmethod
    def on_quote(self, quote: Quote) -> list[Order]:
        """Process new quote and return orders to place."""
        pass

    @abstractmethod
    def on_start(self) -> None:
        """Called when strategy starts."""
        pass

    @abstractmethod
    def on_stop(self) -> None:
        """Called when strategy stops."""
        pass
