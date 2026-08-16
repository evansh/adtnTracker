"""Unit tests for factory classes."""

from unittest.mock import patch

import pytest

from adtn_tracker.broker import SchwabBroker, TradierBroker
from adtn_tracker.config import SchwabConfig, TradierConfig
from adtn_tracker.core import AssetClass
from adtn_tracker.data import YFinanceProvider
from adtn_tracker.factory import BrokerFactory, ProviderFactory, SymbolFactory


class TestProviderFactory:
    """Tests for ProviderFactory."""

    def test_create_yfinance(self):
        provider = ProviderFactory.create("yfinance")
        assert isinstance(provider, YFinanceProvider)

    def test_create_default(self):
        provider = ProviderFactory.create_default()
        assert isinstance(provider, YFinanceProvider)

    def test_unknown_provider(self):
        with pytest.raises(ValueError, match="Unknown provider"):
            ProviderFactory.create("unknown")

    def test_register_provider(self):
        class MockProvider:
            pass

        ProviderFactory.register("mock", MockProvider)
        provider = ProviderFactory.create("mock")
        assert isinstance(provider, MockProvider)

        # Cleanup
        del ProviderFactory._providers["mock"]


class TestBrokerFactory:
    """Tests for BrokerFactory."""

    def test_create_schwab(self):
        config = SchwabConfig(app_key="test", app_secret="test")
        broker = BrokerFactory.create("schwab", config=config)
        assert isinstance(broker, SchwabBroker)

    def test_create_tradier(self):
        config = TradierConfig(access_token="test", account_id="123")
        broker = BrokerFactory.create("tradier", config=config)
        assert isinstance(broker, TradierBroker)

    def test_create_tdameritrade_alias(self):
        config = SchwabConfig(app_key="test", app_secret="test")
        broker = BrokerFactory.create("tdameritrade", config=config)
        assert isinstance(broker, SchwabBroker)

    def test_unknown_broker(self):
        with pytest.raises(ValueError, match="Unknown broker"):
            BrokerFactory.create("unknown")

    @patch("adtn_tracker.factory.get_settings")
    def test_create_from_config_schwab(self, mock_settings):
        mock_settings.return_value.schwab = SchwabConfig(app_key="test", app_secret="test")
        mock_settings.return_value.tradier = TradierConfig()

        broker = BrokerFactory.create_from_config("schwab")
        assert isinstance(broker, SchwabBroker)

    @patch("adtn_tracker.factory.get_settings")
    def test_create_from_config_tradier(self, mock_settings):
        mock_settings.return_value.schwab = SchwabConfig()
        mock_settings.return_value.tradier = TradierConfig(access_token="test", account_id="123")

        broker = BrokerFactory.create_from_config("tradier")
        assert isinstance(broker, TradierBroker)


class TestSymbolFactory:
    """Tests for SymbolFactory."""

    def test_create_equity(self):
        sym = SymbolFactory.create("ADTN")
        assert sym.ticker == "ADTN"
        assert sym.asset_class == AssetClass.EQUITY

    def test_create_with_asset_class(self):
        sym = SymbolFactory.create("AAPL", asset_class="option")
        assert sym.asset_class == AssetClass.OPTION

    def test_create_with_exchange(self):
        sym = SymbolFactory.create("ADTN", exchange="NASDAQ")
        assert sym.exchange == "NASDAQ"

    def test_create_option(self):
        sym = SymbolFactory.create_option("AAPL", "2024-01-19", 150.0, "call")
        assert sym.asset_class == AssetClass.OPTION
        assert "AAPL" in sym.ticker
        assert "C" in sym.ticker  # Call indicator

    def test_parse_option(self):
        sym = SymbolFactory.create_option("AAPL", "2024-01-19", 150.0, "call")
        parsed = SymbolFactory.parse_option(sym)

        assert parsed["underlying"] == "AAPL"
        assert parsed["expiration"] == "2024-01-19"
        assert parsed["type"] == "call"
        assert parsed["strike"] == 150.0

    def test_parse_option_put(self):
        sym = SymbolFactory.create_option("AAPL", "2024-01-19", 150.0, "put")
        parsed = SymbolFactory.parse_option(sym)
        assert parsed["type"] == "put"

    def test_parse_non_option_raises(self):
        sym = SymbolFactory.create("AAPL")
        with pytest.raises(ValueError, match="Not an option symbol"):
            SymbolFactory.parse_option(sym)
