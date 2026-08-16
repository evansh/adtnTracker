"""Schwab/TD Ameritrade broker implementation with OAuth2."""

import json
import logging
import webbrowser
from datetime import datetime, timedelta
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from threading import Thread
from urllib.parse import parse_qs, urlparse

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from adtn_tracker.config import SchwabConfig, get_settings
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


class OAuthCallbackHandler(BaseHTTPRequestHandler):
    """HTTP handler for OAuth callback."""

    def __init__(self, *args, auth_code_container=None, **kwargs):
        self.auth_code_container = auth_code_container
        super().__init__(*args, **kwargs)

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/callback":
            params = parse_qs(parsed.query)
            if "code" in params:
                self.auth_code_container["code"] = params["code"][0]
                self.send_response(200)
                self.send_header("Content-type", "text/html")
                self.end_headers()
                self.wfile.write(b"<h1>Authentication successful! You can close this window.</h1>")
            else:
                self.send_response(400)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass


class SchwabBroker(Broker):
    """Schwab/TD Ameritrade broker integration."""

    BASE_URLS = {
        True: "https://api.schwabapi.com",  # Sandbox
        False: "https://api.schwabapi.com",  # Production (same domain now)
    }

    AUTH_URL = "https://api.schwabapi.com/v1/oauth/authorize"  # nosec B105
    TOKEN_URL = "https://api.schwabapi.com/v1/oauth/token"  # nosec B105

    def __init__(self, config: SchwabConfig | None = None):
        self._config = config or get_settings().schwab
        self._token_path = Path(self._config.token_path).expanduser()
        self._token_path.parent.mkdir(parents=True, exist_ok=True)

        self._access_token: str | None = None
        self._refresh_token: str | None = None
        self._token_expires_at: datetime | None = None
        self._connected = False

        self._session = self._create_session()
        self._load_tokens()

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

    def _load_tokens(self) -> None:
        if self._token_path.exists():
            try:
                with open(self._token_path) as f:
                    data = json.load(f)
                self._access_token = data.get("access_token")
                self._refresh_token = data.get("refresh_token")
                expires_at = data.get("expires_at")
                if expires_at:
                    self._token_expires_at = datetime.fromisoformat(expires_at)
                logger.info("Loaded saved tokens")
            except Exception as e:
                logger.warning(f"Failed to load tokens: {e}")

    def _save_tokens(self) -> None:
        try:
            data = {
                "access_token": self._access_token,
                "refresh_token": self._refresh_token,
                "expires_at": self._token_expires_at.isoformat()
                if self._token_expires_at
                else None,
            }
            with open(self._token_path, "w") as f:
                json.dump(data, f)
            logger.debug("Tokens saved")
        except Exception as e:
            logger.error(f"Failed to save tokens: {e}")

    def _is_token_valid(self) -> bool:
        if not self._access_token or not self._token_expires_at:
            return False
        # Refresh 5 minutes before expiry
        return datetime.now() < (self._token_expires_at - timedelta(minutes=5))

    def _get_auth_headers(self) -> dict:
        if not self._is_token_valid():
            self._refresh_access_token()
        return {"Authorization": f"Bearer {self._access_token}"}

    def _refresh_access_token(self) -> None:
        if not self._refresh_token:
            raise RuntimeError("No refresh token available. Run authenticate() first.")

        logger.info("Refreshing access token...")
        data = {
            "grant_type": "refresh_token",
            "refresh_token": self._refresh_token,
            "client_id": self._config.app_key,
            "client_secret": self._config.app_secret,
        }

        response = self._session.post(self.TOKEN_URL, data=data)
        response.raise_for_status()
        token_data = response.json()

        self._access_token = token_data["access_token"]
        self._refresh_token = token_data.get("refresh_token", self._refresh_token)
        expires_in = token_data.get("expires_in", 1800)
        self._token_expires_at = datetime.now() + timedelta(seconds=expires_in)

        self._save_tokens()
        logger.info("Access token refreshed")

    def authenticate(self) -> None:
        """Run OAuth2 authorization code flow."""
        if self._is_token_valid():
            logger.info("Already authenticated with valid token")
            return

        if not self._config.app_key or not self._config.app_secret:
            raise ValueError(
                "App key and secret required. Set SCHWAB_APP_KEY and SCHWAB_APP_SECRET."
            )

        auth_code = {}

        def run_server():
            server = HTTPServer(
                ("localhost", 8080),
                lambda *args, **kwargs: OAuthCallbackHandler(
                    *args, auth_code_container=auth_code, **kwargs
                ),
            )
            server.handle_request()

        # Start callback server
        server_thread = Thread(target=run_server, daemon=True)
        server_thread.start()

        # Build auth URL
        auth_params = {
            "client_id": self._config.app_key,
            "redirect_uri": self._config.redirect_uri,
            "response_type": "code",
            "scope": "readonly trade market_data",
        }
        auth_url = f"{self.AUTH_URL}?{'&'.join(f'{k}={v}' for k, v in auth_params.items())}"

        logger.info(f"Opening browser for authentication: {auth_url}")
        webbrowser.open(auth_url)

        # Wait for callback
        server_thread.join(timeout=120)

        if "code" not in auth_code:
            raise RuntimeError("Authentication timed out or failed")

        # Exchange code for tokens
        self._exchange_code_for_tokens(auth_code["code"])
        self._connected = True
        logger.info("Authentication successful")

    def _exchange_code_for_tokens(self, code: str) -> None:
        data = {
            "grant_type": "authorization_code",
            "code": code,
            "client_id": self._config.app_key,
            "client_secret": self._config.app_secret,
            "redirect_uri": self._config.redirect_uri,
        }

        response = self._session.post(self.TOKEN_URL, data=data)
        response.raise_for_status()
        token_data = response.json()

        self._access_token = token_data["access_token"]
        self._refresh_token = token_data["refresh_token"]
        expires_in = token_data.get("expires_in", 1800)
        self._token_expires_at = datetime.now() + timedelta(seconds=expires_in)

        self._save_tokens()

    def connect(self) -> None:
        """Establish connection (authenticate if needed)."""
        if not self._is_token_valid():
            self.authenticate()
        else:
            self._connected = True
        logger.info("Schwab broker connected")

    def disconnect(self) -> None:
        self._connected = False
        logger.info("Schwab broker disconnected")

    def is_connected(self) -> bool:
        return self._connected and self._is_token_valid()

    def _request(self, method: str, endpoint: str, **kwargs) -> requests.Response:
        url = f"{self.BASE_URLS[self._config.use_sandbox]}{endpoint}"
        headers = kwargs.pop("headers", {})
        headers.update(self._get_auth_headers())

        response = self._session.request(method, url, headers=headers, **kwargs)

        if response.status_code == 401:
            # Token expired, refresh and retry
            self._refresh_access_token()
            headers.update(self._get_auth_headers())
            response = self._session.request(method, url, headers=headers, **kwargs)

        response.raise_for_status()
        return response

    def get_accounts(self) -> list[Account]:
        response = self._request("GET", "/trader/v1/accounts")
        data = response.json()

        accounts = []
        for item in data:
            accounts.append(
                Account(
                    account_id=item.get("hashValue") or item.get("accountNumber", ""),
                    name=item.get("accountType", "Unknown"),
                    buying_power=float(item.get("currentBalances", {}).get("buyingPower", 0)),
                    cash=float(item.get("currentBalances", {}).get("cashBalance", 0)),
                    equity=float(item.get("currentBalances", {}).get("liquidationValue", 0)),
                    currency="USD",
                    raw=item,
                )
            )
        return accounts

    def get_account(self, account_id: str) -> Account:
        response = self._request("GET", f"/trader/v1/accounts/{account_id}")
        item = response.json()

        return Account(
            account_id=item.get("hashValue") or item.get("accountNumber", ""),
            name=item.get("accountType", "Unknown"),
            buying_power=float(item.get("currentBalances", {}).get("buyingPower", 0)),
            cash=float(item.get("currentBalances", {}).get("cashBalance", 0)),
            equity=float(item.get("currentBalances", {}).get("liquidationValue", 0)),
            currency="USD",
            raw=item,
        )

    def get_positions(self, account_id: str) -> list[Position]:
        response = self._request("GET", f"/trader/v1/accounts/{account_id}")
        data = response.json()

        positions = []
        for item in data.get("positions", []):
            instrument = item.get("instrument", {})
            symbol = Symbol(
                ticker=instrument.get("symbol", ""),
                asset_class=AssetClass(instrument.get("assetType", "EQUITY").lower()),
            )
            positions.append(
                Position(
                    account_id=account_id,
                    symbol=symbol,
                    quantity=float(item.get("longQuantity", 0) - item.get("shortQuantity", 0)),
                    avg_entry_price=float(item.get("averagePrice", 0)),
                    current_price=float(item.get("marketValue", 0))
                    / max(abs(item.get("longQuantity", 0) - item.get("shortQuantity", 0)), 1),
                    market_value=float(item.get("marketValue", 0)),
                    unrealized_pnl=float(item.get("currentDayProfitLoss", 0)),
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
        params = {"maxResults": limit}
        if status:
            params["status"] = status.value.upper()

        response = self._request("GET", f"/trader/v1/accounts/{account_id}/orders", params=params)
        data = response.json()

        orders = []
        for item in data:
            orders.append(self._parse_order(item, account_id))
        return orders

    def _parse_order(self, item: dict, account_id: str) -> Order:
        instrument = item.get("orderLegCollection", [{}])[0].get("instrument", {})
        symbol = Symbol(
            ticker=instrument.get("symbol", ""),
            asset_class=AssetClass(instrument.get("assetType", "EQUITY").lower()),
        )

        status_map = {
            "PENDING": OrderStatus.PENDING,
            "OPEN": OrderStatus.OPEN,
            "FILLED": OrderStatus.FILLED,
            "PARTIALLY_FILLED": OrderStatus.PARTIALLY_FILLED,
            "CANCELED": OrderStatus.CANCELLED,
            "REJECTED": OrderStatus.REJECTED,
            "EXPIRED": OrderStatus.EXPIRED,
        }

        return Order(
            order_id=item.get("orderId", ""),
            account_id=account_id,
            symbol=symbol,
            side=OrderSide(
                item.get("orderLegCollection", [{}])[0].get("instruction", "BUY").lower()
            ),
            order_type=OrderType(item.get("orderType", "MARKET").lower()),
            quantity=float(item.get("quantity", 0)),
            limit_price=float(item.get("price", 0)) if item.get("price") else None,
            stop_price=float(item.get("stopPrice", 0)) if item.get("stopPrice") else None,
            status=status_map.get(item.get("status", "PENDING"), OrderStatus.PENDING),
            filled_quantity=float(item.get("filledQuantity", 0)),
            avg_fill_price=float(item.get("averageFillPrice", 0))
            if item.get("averageFillPrice")
            else None,
            created_at=datetime.fromisoformat(item.get("enteredTime", "").replace("Z", "+00:00"))
            if item.get("enteredTime")
            else None,
            updated_at=datetime.fromisoformat(item.get("closeTime", "").replace("Z", "+00:00"))
            if item.get("closeTime")
            else None,
            raw=item,
        )

    def place_order(self, order: Order) -> Order:
        payload = {
            "orderType": order.order_type.value.upper(),
            "session": "NORMAL",
            "duration": "DAY",
            "orderStrategyType": "SINGLE",
            "orderLegCollection": [
                {
                    "instruction": order.side.value.upper(),
                    "quantity": order.quantity,
                    "instrument": {
                        "symbol": order.symbol.ticker,
                        "assetType": order.symbol.asset_class.value.upper(),
                    },
                }
            ],
        }

        if order.order_type in (OrderType.LIMIT, OrderType.STOP_LIMIT):
            payload["price"] = order.limit_price
        if order.order_type in (OrderType.STOP, OrderType.STOP_LIMIT):
            payload["stopPrice"] = order.stop_price

        response = self._request(
            "POST",
            f"/trader/v1/accounts/{order.account_id}/orders",
            json=payload,
        )

        location = response.headers.get("Location", "")
        order_id = location.split("/")[-1] if location else ""

        return Order(
            order_id=order_id,
            account_id=order.account_id,
            symbol=order.symbol,
            side=order.side,
            order_type=order.order_type,
            quantity=order.quantity,
            limit_price=order.limit_price,
            stop_price=order.stop_price,
            status=OrderStatus.PENDING,
            raw=response.json() if response.content else {},
        )

    def cancel_order(self, account_id: str, order_id: str) -> bool:
        response = self._request(
            "DELETE",
            f"/trader/v1/accounts/{account_id}/orders/{order_id}",
        )
        return response.status_code == 200

    def replace_order(self, account_id: str, order_id: str, order: Order) -> Order:
        # Schwab doesn't support replace, cancel + place new
        self.cancel_order(account_id, order_id)
        return self.place_order(order)

    def get_order(self, account_id: str, order_id: str) -> Order:
        response = self._request("GET", f"/trader/v1/accounts/{account_id}/orders/{order_id}")
        return self._parse_order(response.json(), account_id)

    # Market data methods (bonus - can also be used as data provider)
    def get_quotes(self, symbols: list[Symbol]) -> dict[str, dict]:
        """Get real-time quotes for multiple symbols."""
        symbol_str = ",".join(s.ticker for s in symbols)
        response = self._request("GET", "/marketdata/v1/quotes", params={"symbols": symbol_str})
        return response.json()

    def get_option_chain(self, underlying: Symbol, expiration: datetime | None = None) -> dict:
        """Get option chain."""
        params = {"symbol": underlying.ticker}
        if expiration:
            params["toDate"] = expiration.strftime("%Y-%m-%d")
        response = self._request("GET", "/marketdata/v1/chains", params=params)
        return response.json()

    def get_price_history(
        self,
        symbol: Symbol,
        period_type: str = "year",
        period: int = 1,
        frequency_type: str = "daily",
        frequency: int = 1,
    ) -> dict:
        """Get historical price data."""
        params = {
            "periodType": period_type,
            "period": period,
            "frequencyType": frequency_type,
            "frequency": frequency,
        }
        response = self._request(
            "GET", f"/marketdata/v1/{symbol.ticker}/pricehistory", params=params
        )
        return response.json()
