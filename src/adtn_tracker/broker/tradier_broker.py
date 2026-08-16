"""Tradier broker implementation."""

import logging
from datetime import datetime

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from adtn_tracker.config import TradierConfig, get_settings
from adtn_tracker.core import (
    Account,
    AssetClass,
    Broker,
    Order,
    OrderSide,
    OrderStatus,
    OrderType,
    Position,
    Symbol,
)

logger = logging.getLogger(__name__)


class TradierBroker(Broker):
    """Tradier broker integration."""

    BASE_URLS = {
        True: "https://sandbox.tradier.com/v1",  # Sandbox
        False: "https://api.tradier.com/v1",  # Production
    }

    def __init__(self, config: TradierConfig | None = None):
        self._config = config or get_settings().tradier
        self._access_token = self._config.access_token
        self._account_id = self._config.account_id
        self._connected = False

        self._session = self._create_session()

    def _create_session(self) -> requests.Session:
        session = requests.Session()
        retry = Retry(
            total=3,
            backoff_factor=0.5,
            status_forcelist=[429, 500, 502, 503, 504],
            allowed_methods=["GET", "POST", "DELETE", "PUT"],
        )
        adapter = HTTPAdapter(max_retries=retry)
        session.mount("https://", adapter)
        session.mount("http://", adapter)
        return session

    def _get_headers(self) -> dict:
        return {
            "Authorization": f"Bearer {self._access_token}",
            "Accept": "application/json",
        }

    def connect(self) -> None:
        """Verify connection by fetching account."""
        if not self._access_token:
            raise ValueError("Access token required. Set TRADIER_ACCESS_TOKEN.")

        try:
            self.get_account(self._account_id)
            self._connected = True
            logger.info("Tradier broker connected")
        except Exception as e:
            logger.error(f"Connection failed: {e}")
            raise

    def disconnect(self) -> None:
        self._connected = False
        logger.info("Tradier broker disconnected")

    def is_connected(self) -> bool:
        return self._connected

    def _request(self, method: str, endpoint: str, **kwargs) -> requests.Response:
        url = f"{self.BASE_URLS[self._config.use_sandbox]}{endpoint}"
        headers = kwargs.pop("headers", {})
        headers.update(self._get_headers())

        response = self._session.request(method, url, headers=headers, **kwargs)
        response.raise_for_status()
        return response

    def get_accounts(self) -> list[Account]:
        response = self._request("GET", "/user/profile/accounts")
        data = response.json()

        accounts = []
        for item in data.get("accounts", {}).get("account", []):
            accounts.append(
                Account(
                    account_id=str(item.get("account_number", "")),
                    name=item.get("account_type", "Unknown"),
                    buying_power=float(item.get("buying_power", 0)),
                    cash=float(item.get("cash", 0)),
                    equity=float(item.get("total_equity", 0)),
                    currency="USD",
                    raw=item,
                )
            )
        return accounts

    def get_account(self, account_id: str) -> Account:
        response = self._request("GET", "/user/profile/accounts", params={"account_id": account_id})
        data = response.json()

        accounts = data.get("accounts", {}).get("account", [])
        if not accounts:
            raise ValueError(f"Account not found: {account_id}")

        item = accounts[0] if isinstance(accounts, list) else accounts
        return Account(
            account_id=str(item.get("account_number", "")),
            name=item.get("account_type", "Unknown"),
            buying_power=float(item.get("buying_power", 0)),
            cash=float(item.get("cash", 0)),
            equity=float(item.get("total_equity", 0)),
            currency="USD",
            raw=item,
        )

    def get_positions(self, account_id: str) -> list[Position]:
        response = self._request("GET", f"/accounts/{account_id}/positions")
        data = response.json()

        positions = []
        positions_data = data.get("positions", {}).get("position", [])
        if not isinstance(positions_data, list):
            positions_data = [positions_data] if positions_data else []

        for item in positions_data:
            symbol = Symbol(
                ticker=item.get("symbol", ""),
                asset_class=AssetClass.EQUITY,  # Tradier primarily equities/options
            )
            qty = float(item.get("quantity", 0))
            positions.append(
                Position(
                    account_id=account_id,
                    symbol=symbol,
                    quantity=qty,
                    avg_entry_price=float(item.get("cost_basis", 0)) / qty if qty else 0,
                    current_price=float(item.get("current_price", 0)),
                    market_value=float(item.get("market_value", 0)),
                    unrealized_pnl=float(item.get("gain_loss", 0)),
                    raw=item,
                )
            )
        return positions

    def get_orders(
        self,
        account_id: str,
        status: OrderStatus | None = None,
        limit: int = 100,
    ) -> list[Order]:
        params = {"limit": limit}
        if status:
            params["status"] = status.value

        response = self._request("GET", f"/accounts/{account_id}/orders", params=params)
        data = response.json()

        orders = []
        orders_data = data.get("orders", {}).get("order", [])
        if not isinstance(orders_data, list):
            orders_data = [orders_data] if orders_data else []

        for item in orders_data:
            orders.append(self._parse_order(item, account_id))
        return orders

    def _parse_order(self, item: dict, account_id: str) -> Order:
        symbol = Symbol(
            ticker=item.get("symbol", ""),
            asset_class=AssetClass(item.get("type", "stock").lower())
            if item.get("type") in ("stock", "option")
            else AssetClass.EQUITY,
        )

        status_map = {
            "pending": OrderStatus.PENDING,
            "open": OrderStatus.OPEN,
            "filled": OrderStatus.FILLED,
            "partially_filled": OrderStatus.PARTIALLY_FILLED,
            "cancelled": OrderStatus.CANCELLED,
            "rejected": OrderStatus.REJECTED,
            "expired": OrderStatus.EXPIRED,
        }

        return Order(
            order_id=str(item.get("id", "")),
            account_id=account_id,
            symbol=symbol,
            side=OrderSide(item.get("side", "buy").lower()),
            order_type=OrderType(item.get("type", "market").lower().replace("_", "-")),
            quantity=float(item.get("quantity", 0)),
            limit_price=float(item.get("price", 0)) if item.get("price") else None,
            stop_price=float(item.get("stop", 0)) if item.get("stop") else None,
            status=status_map.get(item.get("status", "pending").lower(), OrderStatus.PENDING),
            filled_quantity=float(item.get("exec_quantity", 0)),
            avg_fill_price=float(item.get("avg_fill_price", 0))
            if item.get("avg_fill_price")
            else None,
            created_at=datetime.fromisoformat(item.get("created_at", "").replace("Z", "+00:00"))
            if item.get("created_at")
            else None,
            updated_at=datetime.fromisoformat(item.get("updated_at", "").replace("Z", "+00:00"))
            if item.get("updated_at")
            else None,
            raw=item,
        )

    def place_order(self, order: Order) -> Order:
        payload = {
            "class": order.symbol.asset_class.value,
            "symbol": order.symbol.ticker,
            "side": order.side.value,
            "quantity": order.quantity,
            "type": order.order_type.value.replace("-", "_"),
            "duration": "day",
        }

        if order.order_type in (OrderType.LIMIT, OrderType.STOP_LIMIT):
            payload["price"] = order.limit_price
        if order.order_type in (OrderType.STOP, OrderType.STOP_LIMIT):
            payload["stop"] = order.stop_price

        # Handle options
        if order.symbol.asset_class == AssetClass.OPTION:
            payload["option_symbol"] = order.symbol.ticker
            del payload["symbol"]

        response = self._request("POST", f"/accounts/{order.account_id}/orders", data=payload)
        data = response.json()

        order_data = data.get("order", {})
        return Order(
            order_id=str(order_data.get("id", "")),
            account_id=order.account_id,
            symbol=order.symbol,
            side=order.side,
            order_type=order.order_type,
            quantity=order.quantity,
            limit_price=order.limit_price,
            stop_price=order.stop_price,
            status=OrderStatus.PENDING,
            raw=order_data,
        )

    def cancel_order(self, account_id: str, order_id: str) -> bool:
        response = self._request("DELETE", f"/accounts/{account_id}/orders/{order_id}")
        return response.status_code == 200

    def replace_order(self, account_id: str, order_id: str, order: Order) -> Order:
        # Tradier doesn't support replace, cancel + place new
        self.cancel_order(account_id, order_id)
        return self.place_order(order)

    def get_order(self, account_id: str, order_id: str) -> Order:
        response = self._request("GET", f"/accounts/{account_id}/orders/{order_id}")
        return self._parse_order(response.json().get("order", {}), account_id)

    # Market data methods
    def get_quotes(self, symbols: list[Symbol]) -> dict:
        """Get real-time quotes."""
        symbol_str = ",".join(s.ticker for s in symbols)
        response = self._request("GET", "/markets/quotes", params={"symbols": symbol_str})
        return response.json()

    def get_option_chain(self, underlying: Symbol, expiration: datetime | None = None) -> dict:
        """Get option chain with Greeks."""
        params = {"symbol": underlying.ticker}
        if expiration:
            params["expiration"] = expiration.strftime("%Y-%m-%d")
        params["greeks"] = "true"
        response = self._request("GET", "/markets/options/chains", params=params)
        return response.json()

    def get_price_history(
        self,
        symbol: Symbol,
        interval: str = "daily",
        start: datetime | None = None,
        end: datetime | None = None,
    ) -> dict:
        """Get historical price data."""
        params = {"symbol": symbol.ticker, "interval": interval}
        if start:
            params["start"] = start.strftime("%Y-%m-%d")
        if end:
            params["end"] = end.strftime("%Y-%m-%d")
        response = self._request("GET", "/markets/history", params=params)
        return response.json()

    def get_option_expirations(self, underlying: Symbol) -> list[datetime]:
        """Get available option expirations."""
        response = self._request(
            "GET", "/markets/options/expirations", params={"symbol": underlying.ticker}
        )
        data = response.json()
        expirations = data.get("expirations", {}).get("date", [])
        if not isinstance(expirations, list):
            expirations = [expirations] if expirations else []
        return [datetime.strptime(e, "%Y-%m-%d") for e in expirations]
