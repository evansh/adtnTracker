"""CLI entry point for adtn_tracker."""

import argparse
import logging
import sys
from datetime import datetime, timedelta
from pathlib import Path

import pandas as pd

from .backtest import BacktestConfig, SimpleBacktester, generate_candlestick_signals
from .config import ENV_TEMPLATE, get_settings, load_env_file
from .core import TimeFrame
from .data import YFinanceProvider
from .factory import BrokerFactory, SymbolFactory


def setup_logging(level: str = "INFO", log_file: str = None):
    """Configure logging."""
    handlers = [logging.StreamHandler(sys.stdout)]
    if log_file:
        Path(log_file).parent.mkdir(parents=True, exist_ok=True)
        handlers.append(logging.FileHandler(log_file))

    logging.basicConfig(
        level=getattr(logging, level.upper()),
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
        handlers=handlers,
    )


def cmd_fetch_data(args):
    """Fetch historical data."""
    settings = get_settings()
    provider = YFinanceProvider(settings.yfinance)
    provider.connect()

    symbol = SymbolFactory.create(args.symbol, args.asset_class, args.exchange)
    timeframe = TimeFrame(args.timeframe)

    end = datetime.now()
    start = end - timedelta(days=args.days) if args.days else end - timedelta(days=365)

    print(f"Fetching {symbol} {timeframe.value} from {start.date()} to {end.date()}")
    bars = provider.get_bars(symbol, timeframe, start, end)

    if not bars:
        print("No data returned")
        return

    df = pd.DataFrame(
        [
            {
                "timestamp": b.timestamp,
                "open": b.open,
                "high": b.high,
                "low": b.low,
                "close": b.close,
                "volume": b.volume,
            }
            for b in bars
        ]
    )

    print(f"Got {len(df)} bars")
    print(df.head())
    print(df.tail())

    if args.output:
        output_path = Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        df.to_parquet(output_path, index=False)
        print(f"Saved to {output_path}")


def cmd_backtest(args):
    """Run backtest."""
    settings = get_settings()
    provider = YFinanceProvider(settings.yfinance)
    provider.connect()

    symbol = SymbolFactory.create(args.symbol, args.asset_class, args.exchange)
    timeframe = TimeFrame(args.timeframe)

    end = datetime.now()
    start = end - timedelta(days=args.days) if args.days else end - timedelta(days=730)

    print("Fetching data for backtest...")
    bars = provider.get_bars(symbol, timeframe, start, end)

    if not bars:
        print("No data for backtest")
        return

    df = pd.DataFrame(
        [
            {
                "symbol": str(symbol),
                "timestamp": b.timestamp,
                "open": b.open,
                "high": b.high,
                "low": b.low,
                "close": b.close,
                "volume": b.volume,
            }
            for b in bars
        ]
    )

    signals = generate_candlestick_signals(df)

    config = BacktestConfig(
        initial_capital=args.capital,
        position_size_pct=args.position_size,
        commission_per_share=args.commission,
        slippage_pct=args.slippage,
    )

    backtester = SimpleBacktester(config)
    metrics = backtester.run(df, signals)

    trades_df = backtester.get_trades_df()
    equity_df = backtester.get_equity_curve_df()

    print("\n=== BACKTEST RESULTS ===")
    print(f"Symbol: {symbol}")
    print(f"Period: {start.date()} to {end.date()}")
    print(f"Initial Capital: ${args.capital:,.2f}")
    print(f"Final Equity: ${metrics.get('final_equity', 0):,.2f}")
    print(f"Total Return: {metrics.get('total_return', 0):.2%}")
    print(f"CAGR: {metrics.get('cagr', 0):.2%}")
    print(f"Sharpe Ratio: {metrics.get('sharpe', 0):.2f}")
    print(f"Max Drawdown: {metrics.get('max_drawdown', 0):.2%}")
    print(f"Win Rate: {metrics.get('win_rate', 0):.2%}")
    print(f"Profit Factor: {metrics.get('profit_factor', 0):.2f}")
    print(f"Number of Trades: {metrics.get('num_trades', 0)}")

    if args.output:
        output_dir = Path(args.output)
        output_dir.mkdir(parents=True, exist_ok=True)
        trades_df.to_csv(output_dir / "trades.csv", index=False)
        equity_df.to_csv(output_dir / "equity_curve.csv", index=False)
        import json

        with open(output_dir / "metrics.json", "w") as f:
            json.dump(metrics, f, indent=2, default=str)
        print(f"\nResults saved to {output_dir}")


def cmd_broker_info(args):
    """Show broker account info."""
    broker = BrokerFactory.create_from_config(args.broker)
    broker.connect()

    accounts = broker.get_accounts()
    for acc in accounts:
        print(f"\nAccount: {acc.account_id} ({acc.name})")
        print(f"  Equity: ${acc.equity:,.2f}")
        print(f"  Cash: ${acc.cash:,.2f}")
        print(f"  Buying Power: ${acc.buying_power:,.2f}")

        positions = broker.get_positions(acc.account_id)
        if positions:
            print(f"  Positions ({len(positions)}):")
            for pos in positions:
                print(
                    f"    {pos.symbol}: {pos.quantity} @ ${pos.avg_entry_price:.2f} = ${pos.market_value:,.2f} (PnL: ${pos.unrealized_pnl:,.2f})"
                )


def cmd_place_order(args):
    """Place an order (paper/sandbox only)."""
    broker = BrokerFactory.create_from_config(args.broker)
    broker.connect()

    accounts = broker.get_accounts()
    if not accounts:
        print("No accounts found")
        return

    account = accounts[0]
    print(f"Using account: {account.account_id}")

    symbol = SymbolFactory.create(args.symbol, args.asset_class, args.exchange)

    from .core import Order, OrderSide, OrderType

    order = Order(
        order_id="",
        account_id=account.account_id,
        symbol=symbol,
        side=OrderSide(args.side),
        order_type=OrderType(args.order_type),
        quantity=args.quantity,
        limit_price=args.limit_price,
        stop_price=args.stop_price,
    )

    if args.dry_run:
        print(f"DRY RUN: Would place {order}")
        return

    confirm = input(f"Place order? {order} (y/N): ")
    if confirm.lower() != "y":
        print("Cancelled")
        return

    result = broker.place_order(order)
    print(f"Order placed: {result.order_id} - {result.status}")


def cmd_generate_env(args):
    """Generate .env template."""
    env_path = Path(args.output) if args.output else Path(".env")
    env_path.write_text(ENV_TEMPLATE)
    print(f"Generated {env_path}")


def main():
    parser = argparse.ArgumentParser(
        description="adtn_tracker - Stock tracking and trading framework"
    )
    parser.add_argument("--env", help="Path to .env file")
    parser.add_argument("--log-level", default="INFO", help="Log level")
    parser.add_argument("--log-file", help="Log file path")

    subparsers = parser.add_subparsers(dest="command", help="Commands")

    # fetch-data
    p_fetch = subparsers.add_parser("fetch-data", help="Fetch historical data")
    p_fetch.add_argument("symbol", help="Symbol (e.g., ADTN)")
    p_fetch.add_argument("--asset-class", default="equity", choices=["equity", "option"])
    p_fetch.add_argument("--exchange", help="Exchange (optional)")
    p_fetch.add_argument("--timeframe", default="1d", choices=[t.value for t in TimeFrame])
    p_fetch.add_argument("--days", type=int, help="Days of history")
    p_fetch.add_argument("--output", help="Output parquet file")
    p_fetch.set_defaults(func=cmd_fetch_data)

    # backtest
    p_backtest = subparsers.add_parser("backtest", help="Run backtest")
    p_backtest.add_argument("symbol", help="Symbol (e.g., ADTN)")
    p_backtest.add_argument("--asset-class", default="equity", choices=["equity", "option"])
    p_backtest.add_argument("--exchange", help="Exchange (optional)")
    p_backtest.add_argument("--timeframe", default="1d", choices=[t.value for t in TimeFrame])
    p_backtest.add_argument("--days", type=int, help="Days of history")
    p_backtest.add_argument("--capital", type=float, default=100000)
    p_backtest.add_argument("--position-size", type=float, default=0.10)
    p_backtest.add_argument("--commission", type=float, default=0.005)
    p_backtest.add_argument("--slippage", type=float, default=0.001)
    p_backtest.add_argument("--output", help="Output directory")
    p_backtest.set_defaults(func=cmd_backtest)

    # broker-info
    p_broker = subparsers.add_parser("broker-info", help="Show broker account info")
    p_broker.add_argument("--broker", choices=["schwab", "tradier"], help="Broker to use")
    p_broker.set_defaults(func=cmd_broker_info)

    # place-order
    p_order = subparsers.add_parser("place-order", help="Place an order")
    p_order.add_argument("symbol", help="Symbol (e.g., ADTN)")
    p_order.add_argument("side", choices=["buy", "sell"])
    p_order.add_argument("quantity", type=float)
    p_order.add_argument(
        "--order-type", default="market", choices=["market", "limit", "stop", "stop_limit"]
    )
    p_order.add_argument("--limit-price", type=float)
    p_order.add_argument("--stop-price", type=float)
    p_order.add_argument("--asset-class", default="equity", choices=["equity", "option"])
    p_order.add_argument("--exchange", help="Exchange (optional)")
    p_order.add_argument("--broker", choices=["schwab", "tradier"], help="Broker to use")
    p_order.add_argument("--dry-run", action="store_true", help="Don't actually place order")
    p_order.set_defaults(func=cmd_place_order)

    # generate-env
    p_env = subparsers.add_parser("generate-env", help="Generate .env template")
    p_env.add_argument("--output", default=".env", help="Output path")
    p_env.set_defaults(func=cmd_generate_env)

    args = parser.parse_args()

    if args.env:
        load_env_file(args.env)

    setup_logging(args.log_level, args.log_file)

    if not hasattr(args, "func"):
        parser.print_help()
        return 1

    try:
        args.func(args)
    except Exception as e:
        logging.error(f"Error: {e}")
        if args.log_level == "DEBUG":
            import traceback

            traceback.print_exc()
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
