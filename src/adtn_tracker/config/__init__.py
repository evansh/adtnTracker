"""Configuration management for adtn_tracker."""

from functools import lru_cache
from pathlib import Path

from pydantic import BaseModel, Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class SchwabConfig(BaseModel):
    """Schwab/TD Ameritrade configuration."""

    app_key: str = Field(default="", description="Schwab App Key (Client ID)")
    app_secret: str = Field(default="", description="Schwab App Secret")
    redirect_uri: str = Field(
        default="http://localhost:8080/callback", description="OAuth redirect URI"
    )
    token_path: str = Field(
        default="~/.adtn_tracker/schwab_tokens.json", description="Token storage path"
    )
    use_sandbox: bool = Field(default=True, description="Use sandbox environment")
    rate_limit_per_second: int = Field(default=100, description="Rate limit requests per second")


class TradierConfig(BaseModel):
    """Tradier configuration."""

    access_token: str = Field(default="", description="Tradier access token")
    account_id: str = Field(default="", description="Tradier account ID")
    use_sandbox: bool = Field(default=True, description="Use sandbox environment")
    base_url: str = Field(default="", description="Custom base URL (optional)")
    rate_limit_per_second: int = Field(default=10, description="Rate limit requests per second")


class YFinanceConfig(BaseModel):
    """Yahoo Finance configuration."""

    cache_dir: str = Field(default="data", description="Cache directory for parquet files")
    timeout: int = Field(default=30, description="Request timeout in seconds")
    max_retries: int = Field(default=3, description="Max retry attempts")


class BacktestConfig(BaseModel):
    """Backtesting configuration."""

    initial_capital: float = Field(default=100000.0)
    position_size_pct: float = Field(default=0.10)
    commission_per_share: float = Field(default=0.005)
    slippage_pct: float = Field(default=0.001)
    min_trade_size: int = Field(default=1)
    default_timeframe: str = Field(default="1d")


class LoggingConfig(BaseModel):
    """Logging configuration."""

    level: str = Field(default="INFO")
    format: str = Field(default="%(asctime)s - %(name)s - %(levelname)s - %(message)s")
    file: str | None = Field(default=None, description="Log file path (optional)")


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
        env_nested_delimiter="__",
    )

    # Environment
    environment: str = Field(
        default="development", description="Environment: development, staging, production"
    )
    debug: bool = Field(default=False)

    # Data providers
    yfinance: YFinanceConfig = Field(default_factory=YFinanceConfig)

    # Brokers
    schwab: SchwabConfig = Field(default_factory=SchwabConfig)
    tradier: TradierConfig = Field(default_factory=TradierConfig)

    # Backtesting
    backtest: BacktestConfig = Field(default_factory=BacktestConfig)

    # Logging
    logging: LoggingConfig = Field(default_factory=LoggingConfig)

    # API Keys (for external services)
    polygon_api_key: str = Field(default="", description="Polygon.io API key")
    tiingo_api_key: str = Field(default="", description="Tiingo API key")


@lru_cache
def get_settings() -> Settings:
    """Get cached settings instance."""
    return Settings()


def load_env_file(env_path: str | None = None) -> None:
    """Load environment variables from file."""
    if env_path:
        from dotenv import load_dotenv

        load_dotenv(env_path, override=True)
    else:
        # Try default locations
        for path in [".env", ".env.local", ".env.development"]:
            if Path(path).exists():
                from dotenv import load_dotenv

                load_dotenv(path, override=True)
                break


# Example .env template
ENV_TEMPLATE = """# adtn_tracker Environment Configuration
# Copy to .env and fill in your values

# Environment
ENVIRONMENT=development
DEBUG=true

# Yahoo Finance
YFINANCE_CACHE_DIR=data
YFINANCE_TIMEOUT=30
YFINANCE_MAX_RETRIES=3

# Schwab / TD Ameritrade
SCHWAB_APP_KEY=your_app_key
SCHWAB_APP_SECRET=your_app_secret
SCHWAB_REDIRECT_URI=http://localhost:8080/callback
SCHWAB_TOKEN_PATH=~/.adtn_tracker/schwab_tokens.json
SCHWAB_USE_SANDBOX=true
SCHWAB_RATE_LIMIT_PER_SECOND=100

# Tradier
TRADIER_ACCESS_TOKEN=your_access_token
TRADIER_ACCOUNT_ID=your_account_id
TRADIER_USE_SANDBOX=true
TRADIER_RATE_LIMIT_PER_SECOND=10

# Backtest
BACKTEST_INITIAL_CAPITAL=100000
BACKTEST_POSITION_SIZE_PCT=0.10
BACKTEST_COMMISSION_PER_SHARE=0.005
BACKTEST_SLIPPAGE_PCT=0.001

# Logging
LOGGING_LEVEL=INFO
LOGGING_FILE=logs/adtn_tracker.log

# External APIs (optional)
POLYGON_API_KEY=
TIINGO_API_KEY=
"""
