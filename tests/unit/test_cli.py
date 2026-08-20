"""Unit tests for CLI entry point."""

import subprocess
import sys
import pytest


class TestCLI:
    """Tests for CLI entry point."""

    def test_cli_help(self):
        """Test that CLI help works."""
        result = subprocess.run(
            [sys.executable, "-m", "adtn_tracker.cli", "--help"],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0
        assert "adtn_tracker" in result.stdout
        assert "fetch-data" in result.stdout
        assert "backtest" in result.stdout
        assert "broker-info" in result.stdout
        assert "place-order" in result.stdout
        assert "generate-env" in result.stdout

    def test_cli_fetch_data_help(self):
        """Test fetch-data subcommand help."""
        result = subprocess.run(
            [sys.executable, "-m", "adtn_tracker.cli", "fetch-data", "--help"],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0
        assert "symbol" in result.stdout
        assert "timeframe" in result.stdout

    def test_cli_backtest_help(self):
        """Test backtest subcommand help."""
        result = subprocess.run(
            [sys.executable, "-m", "adtn_tracker.cli", "backtest", "--help"],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0
        assert "symbol" in result.stdout
        assert "capital" in result.stdout

    def test_cli_generate_env(self, tmp_path):
        """Test generate-env command."""
        env_file = tmp_path / ".env.test"
        result = subprocess.run(
            [sys.executable, "-m", "adtn_tracker.cli", "generate-env", "--output", str(env_file)],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0
        assert env_file.exists()
        content = env_file.read_text()
        assert "ENVIRONMENT=" in content
        assert "YFINANCE_" in content
        assert "SCHWAB_" in content
        assert "TRADIER_" in content

    def test_adtn_tracker_console_script(self):
        """Test that the console script entry point works."""
        result = subprocess.run(
            ["adtn-tracker", "--help"],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0
        assert "adtn_tracker" in result.stdout

    def test_cli_value_wheel_help(self):
        """Test value-wheel subcommand help."""
        result = subprocess.run(
            [sys.executable, "-m", "adtn_tracker.cli", "value-wheel", "--help"],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0
        assert "symbol" in result.stdout
        assert "years" in result.stdout
        assert "threshold" in result.stdout
        assert "strike" in result.stdout

    def test_cli_value_wheel_analysis(self):
        """Test value-wheel analysis runs."""
        result = subprocess.run(
            [sys.executable, "-m", "adtn_tracker.cli", "value-wheel", "ADTN", "--years", "2"],
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0
        assert "VALUE WHEEL ANALYSIS" in result.stdout
        assert "BUY" in result.stdout or "WAIT" in result.stdout