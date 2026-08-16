"""Unit tests for configuration."""

from adtn_tracker.config import (
    ENV_TEMPLATE,
    BacktestConfig,
    SchwabConfig,
    Settings,
    TradierConfig,
    YFinanceConfig,
)


class TestYFinanceConfig:
    """Tests for YFinanceConfig."""

    def test_defaults(self):
        config = YFinanceConfig()
        assert config.cache_dir == "data"
        assert config.timeout == 30
        assert config.max_retries == 3

    def test_custom_values(self):
        config = YFinanceConfig(cache_dir="custom_data", timeout=60, max_retries=5)
        assert config.cache_dir == "custom_data"
        assert config.timeout == 60
        assert config.max_retries == 5


class TestSchwabConfig:
    """Tests for SchwabConfig."""

    def test_defaults(self):
        config = SchwabConfig()
        assert config.app_key == ""
        assert config.app_secret == ""
        assert config.redirect_uri == "http://localhost:8080/callback"
        assert config.use_sandbox is True
        assert config.rate_limit_per_second == 100


class TestTradierConfig:
    """Tests for TradierConfig."""

    def test_defaults(self):
        config = TradierConfig()
        assert config.access_token == ""
        assert config.account_id == ""
        assert config.use_sandbox is True
        assert config.rate_limit_per_second == 10


class TestBacktestConfig:
    """Tests for BacktestConfig."""

    def test_defaults(self):
        config = BacktestConfig()
        assert config.initial_capital == 100000.0
        assert config.position_size_pct == 0.10
        assert config.commission_per_share == 0.005
        assert config.slippage_pct == 0.001


class TestSettings:
    """Tests for Settings (pydantic-settings)."""

    def test_default_settings(self):
        settings = Settings()
        assert settings.environment == "development"
        assert settings.debug is False
        assert isinstance(settings.yfinance, YFinanceConfig)
        assert isinstance(settings.schwab, SchwabConfig)
        assert isinstance(settings.tradier, TradierConfig)
        assert isinstance(settings.backtest, BacktestConfig)

    def test_env_override(self, monkeypatch):
        monkeypatch.setenv("ENVIRONMENT", "production")
        monkeypatch.setenv("DEBUG", "true")
        # For nested models, pydantic-settings uses __ as separator
        monkeypatch.setenv("YFINANCE__CACHE_DIR", "/custom/cache")
        monkeypatch.setenv("SCHWAB__APP_KEY", "test_key")
        monkeypatch.setenv("TRADIER__ACCESS_TOKEN", "test_token")

        settings = Settings()
        assert settings.environment == "production"
        assert settings.debug is True
        assert settings.yfinance.cache_dir == "/custom/cache"
        assert settings.schwab.app_key == "test_key"
        assert settings.tradier.access_token == "test_token"

    def test_case_insensitive_env(self, monkeypatch):
        monkeypatch.setenv("environment", "staging")  # lowercase
        settings = Settings()
        assert settings.environment == "staging"


class TestEnvTemplate:
    """Tests for ENV_TEMPLATE."""

    def test_template_contains_required_sections(self):
        assert "ENVIRONMENT=" in ENV_TEMPLATE
        assert "YFINANCE_" in ENV_TEMPLATE
        assert "SCHWAB_" in ENV_TEMPLATE
        assert "TRADIER_" in ENV_TEMPLATE
        assert "BACKTEST_" in ENV_TEMPLATE
        assert "LOGGING_" in ENV_TEMPLATE
        assert "POLYGON_API_KEY" in ENV_TEMPLATE
        assert "TIINGO_API_KEY" in ENV_TEMPLATE

    def test_template_is_valid_syntax(self):
        # Should be parseable as key=value pairs
        lines = ENV_TEMPLATE.strip().split("\n")
        for line in lines:
            line = line.strip()
            if line and not line.startswith("#"):
                assert "=" in line, f"Invalid line: {line}"
