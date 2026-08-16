"""adtn_tracker - Extensible stock tracking and trading framework.

Architecture follows SOLID principles:
- Abstract base classes for DataProvider, Broker, Strategy
- Concrete implementations: YFinanceProvider, SchwabBroker, TradierBroker
- Configuration via environment variables (pydantic-settings)
- Dependency injection for testability
"""

from .config import ENV_TEMPLATE, Settings, get_settings, load_env_file
from .core import (
    Account,
    AssetClass,
    Bar,
    Broker,
    # Abstract bases
    DataProvider,
    OptionContract,
    OptionQuote,
    Order,
    OrderSide,
    OrderStatus,
    OrderType,
    Position,
    Quote,
    Strategy,
    # Data classes
    Symbol,
    # Enums
    TimeFrame,
)

__version__ = "0.2.0"

__all__ = [
    # Config
    "Settings",
    "get_settings",
    "load_env_file",
    "ENV_TEMPLATE",
    # Core enums
    "TimeFrame",
    "OrderSide",
    "OrderType",
    "OrderStatus",
    "AssetClass",
    # Core data classes
    "Symbol",
    "Quote",
    "Bar",
    "OptionContract",
    "OptionQuote",
    "Account",
    "Position",
    "Order",
    # Abstract bases
    "DataProvider",
    "Broker",
    "Strategy",
]
