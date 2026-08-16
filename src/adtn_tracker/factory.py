"""Factory for creating data providers and brokers."""

from datetime import datetime

from .broker import SchwabBroker, TradierBroker
from .config import get_settings
from .core import AssetClass, Broker, DataProvider, Symbol
from .data import YFinanceProvider


class ProviderFactory:
    """Factory for creating data providers."""

    _providers: dict[str, type[DataProvider]] = {
        "yfinance": YFinanceProvider,
    }

    @classmethod
    def register(cls, name: str, provider_class: type[DataProvider]) -> None:
        """Register a new provider."""
        cls._providers[name.lower()] = provider_class

    @classmethod
    def create(cls, name: str, **kwargs) -> DataProvider:
        """Create a provider instance."""
        provider_class = cls._providers.get(name.lower())
        if not provider_class:
            raise ValueError(f"Unknown provider: {name}. Available: {list(cls._providers.keys())}")
        return provider_class(**kwargs)

    @classmethod
    def create_default(cls) -> DataProvider:
        """Create default provider (yfinance)."""
        return cls.create("yfinance")


class BrokerFactory:
    """Factory for creating brokers."""

    _brokers: dict[str, type[Broker]] = {
        "schwab": SchwabBroker,
        "tdameritrade": SchwabBroker,  # Alias
        "tradier": TradierBroker,
    }

    @classmethod
    def register(cls, name: str, broker_class: type[Broker]) -> None:
        """Register a new broker."""
        cls._brokers[name.lower()] = broker_class

    @classmethod
    def create(cls, name: str, **kwargs) -> Broker:
        """Create a broker instance."""
        broker_class = cls._brokers.get(name.lower())
        if not broker_class:
            raise ValueError(f"Unknown broker: {name}. Available: {list(cls._brokers.keys())}")
        return broker_class(**kwargs)

    @classmethod
    def create_from_config(cls, name: str = None) -> Broker:
        """Create broker from configuration."""
        settings = get_settings()

        if name is None:
            # Auto-detect based on available credentials
            if settings.schwab.app_key and settings.schwab.app_secret:
                name = "schwab"
            elif settings.tradier.access_token:
                name = "tradier"
            else:
                raise ValueError("No broker credentials configured")

        if name.lower() == "schwab":
            return SchwabBroker(settings.schwab)
        elif name.lower() == "tradier":
            return TradierBroker(settings.tradier)
        else:
            return cls.create(name)


class SymbolFactory:
    """Factory for creating symbols with normalization."""

    @staticmethod
    def create(ticker: str, asset_class: str = "equity", exchange: str = None) -> Symbol:
        """Create symbol from string."""
        from .core import AssetClass

        return Symbol(
            ticker=ticker.upper(),
            asset_class=AssetClass(asset_class.lower()),
            exchange=exchange.upper() if exchange else None,
        )

    @staticmethod
    def create_option(
        underlying: str,
        expiration: str,  # YYYY-MM-DD
        strike: float,
        option_type: str,  # 'call' or 'put'
    ) -> Symbol:
        """Create option symbol (OCC format)."""
        # OCC format: AAPL  240119C00150000 (6-char expiration: YYMMDD)
        exp_date = datetime.strptime(expiration, "%Y-%m-%d")
        exp = exp_date.strftime("%y%m%d")  # 2-digit year
        strike_str = f"{int(strike * 1000):08d}"
        type_char = "C" if option_type.lower() == "call" else "P"
        occ_symbol = f"{underlying.upper():<6}{exp}{type_char}{strike_str}"
        return Symbol(ticker=occ_symbol, asset_class=AssetClass.OPTION)

    @staticmethod
    def parse_option(symbol: Symbol) -> dict:
        """Parse OCC option symbol."""
        if symbol.asset_class != AssetClass.OPTION:
            raise ValueError("Not an option symbol")

        ticker = symbol.ticker
        if len(ticker) < 21:
            raise ValueError("Invalid OCC symbol format")

        return {
            "underlying": ticker[:6].strip(),
            "expiration": f"20{ticker[6:8]}-{ticker[8:10]}-{ticker[10:12]}",
            "type": "call" if ticker[12] == "C" else "put",
            "strike": int(ticker[13:]) / 1000,
        }
