"""Unit tests for core domain models."""

from datetime import datetime

from adtn_tracker.core import (
    Account,
    AssetClass,
    Bar,
    OptionContract,
    Order,
    OrderSide,
    OrderStatus,
    OrderType,
    Position,
    Quote,
    Symbol,
    TimeFrame,
)


class TestSymbol:
    """Tests for Symbol value object."""

    def test_create_equity_symbol(self):
        sym = Symbol(ticker="ADTN", asset_class=AssetClass.EQUITY)
        assert sym.ticker == "ADTN"
        assert sym.asset_class == AssetClass.EQUITY
        assert str(sym) == "ADTN"

    def test_create_with_exchange(self):
        sym = Symbol(ticker="ADTN", asset_class=AssetClass.EQUITY, exchange="NASDAQ")
        assert str(sym) == "NASDAQ:ADTN"

    def test_from_string_simple(self):
        sym = Symbol.from_string("AAPL")
        assert sym.ticker == "AAPL"
        assert sym.asset_class == AssetClass.EQUITY
        assert sym.exchange is None

    def test_from_string_with_exchange(self):
        sym = Symbol.from_string("NASDAQ:AAPL")
        assert sym.ticker == "AAPL"
        assert sym.exchange == "NASDAQ"

    def test_case_insensitive(self):
        sym = Symbol.from_string("nasdaq:aapl")
        assert sym.ticker == "AAPL"
        assert sym.exchange == "NASDAQ"


class TestEnums:
    """Tests for enums."""

    def test_timeframe_values(self):
        assert TimeFrame.DAY_1 == "1d"
        assert TimeFrame.HOUR_1 == "1h"
        assert TimeFrame.MINUTE_1 == "1m"

    def test_order_side_values(self):
        assert OrderSide.BUY == "buy"
        assert OrderSide.SELL == "sell"

    def test_order_type_values(self):
        assert OrderType.MARKET == "market"
        assert OrderType.LIMIT == "limit"

    def test_order_status_values(self):
        assert OrderStatus.FILLED == "filled"
        assert OrderStatus.CANCELLED == "cancelled"


class TestQuote:
    """Tests for Quote data class."""

    def test_create_quote(self):
        quote = Quote(
            symbol=Symbol(ticker="ADTN"),
            bid=10.0,
            ask=10.05,
            bid_size=100,
            ask_size=200,
            last=10.02,
            timestamp=datetime.now(),
        )
        assert quote.bid == 10.0
        assert quote.ask == 10.05
        assert quote.last == 10.02
        # spread is a computed property (floating point)
        assert abs((quote.ask - quote.bid) - 0.05) < 1e-10


class TestBar:
    """Tests for Bar data class."""

    def test_create_bar(self):
        bar = Bar(
            symbol=Symbol(ticker="ADTN"),
            timestamp=datetime.now(),
            open=10.0,
            high=10.5,
            low=9.8,
            close=10.2,
            volume=100000,
        )
        assert bar.open == 10.0
        assert bar.high == 10.5
        assert bar.low == 9.8
        assert bar.close == 10.2
        assert bar.volume == 100000


class TestOptionContract:
    """Tests for OptionContract."""

    def test_create_option_contract(self):
        underlying = Symbol(ticker="AAPL", asset_class=AssetClass.EQUITY)
        contract = OptionContract(
            symbol=Symbol(ticker="AAPL240119C00150000", asset_class=AssetClass.OPTION),
            underlying=underlying,
            strike=150.0,
            expiration=datetime(2024, 1, 19),
            option_type="call",
        )
        assert contract.strike == 150.0
        assert contract.option_type == "call"
        assert contract.multiplier == 100


class TestAccount:
    """Tests for Account."""

    def test_create_account(self):
        account = Account(
            account_id="12345",
            name="Individual",
            buying_power=50000.0,
            cash=10000.0,
            equity=100000.0,
        )
        assert account.account_id == "12345"
        assert account.buying_power == 50000.0


class TestPosition:
    """Tests for Position."""

    def test_create_position(self):
        pos = Position(
            account_id="12345",
            symbol=Symbol(ticker="ADTN"),
            quantity=100,
            avg_entry_price=10.0,
            current_price=11.0,
            market_value=1100.0,
            unrealized_pnl=100.0,
        )
        assert pos.quantity == 100
        assert pos.unrealized_pnl == 100.0


class TestOrder:
    """Tests for Order."""

    def test_create_market_order(self):
        order = Order(
            order_id="ord_123",
            account_id="12345",
            symbol=Symbol(ticker="ADTN"),
            side=OrderSide.BUY,
            order_type=OrderType.MARKET,
            quantity=100,
        )
        assert order.side == OrderSide.BUY
        assert order.order_type == OrderType.MARKET
        assert order.limit_price is None
        assert order.stop_price is None

    def test_create_limit_order(self):
        order = Order(
            order_id="ord_123",
            account_id="12345",
            symbol=Symbol(ticker="ADTN"),
            side=OrderSide.BUY,
            order_type=OrderType.LIMIT,
            quantity=100,
            limit_price=10.50,
        )
        assert order.limit_price == 10.50

    def test_create_stop_limit_order(self):
        order = Order(
            order_id="ord_123",
            account_id="12345",
            symbol=Symbol(ticker="ADTN"),
            side=OrderSide.SELL,
            order_type=OrderType.STOP_LIMIT,
            quantity=100,
            limit_price=9.50,
            stop_price=10.00,
        )
        assert order.limit_price == 9.50
        assert order.stop_price == 10.00
